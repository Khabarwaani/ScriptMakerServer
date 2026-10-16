// Render a JSON Schema input object as editable fields while keeping raw JSON authoritative.

function schemaPointer(root, reference) {
  if (reference === '#') return root;
  if (!reference?.startsWith('#/')) return null;
  return reference.slice(2).split('/').reduce((node, part) => node?.[part.replace(/~1/g, '/').replace(/~0/g, '~')], root);
}

function schemaNode(node, root, depth = 0) {
  if (!node || typeof node !== 'object' || depth > 32) return node || {};
  const sources = [node];
  if (node.$ref) sources.push(schemaNode(schemaPointer(root, node.$ref), root, depth + 1));
  for (const part of node.allOf || []) sources.push(schemaNode(part, root, depth + 1));
  const combined = {};
  for (const part of sources) {
    for (const [key, value] of Object.entries(part || {})) {
      if (key === 'properties') combined.properties = {...combined.properties, ...value};
      else if (key === 'required') combined.required = [...new Set([...(combined.required || []), ...value])];
      else if (combined[key] === undefined) combined[key] = value;
    }
  }
  return combined;
}

function schemaInitial(node, root, depth = 0) {
  if (depth > 32) return null;
  node = schemaNode(node, root, depth);
  if (Object.hasOwn(node, 'default')) return structuredClone(node.default);
  if (node.examples?.length) return structuredClone(node.examples[0]);
  if (Object.hasOwn(node, 'const')) return structuredClone(node.const);
  if (node.enum?.length) return structuredClone(node.enum[0]);
  const type = Array.isArray(node.type) ? node.type.find(value => value !== 'null') || node.type[0] : node.type;
  if (type === 'object' || node.properties) {
    const object = {};
    for (const key of node.required || []) object[key] = schemaInitial(node.properties?.[key] || {}, root, depth + 1);
    return object;
  }
  if (type === 'array') return [];
  if (type === 'boolean') return false;
  if (type === 'integer' || type === 'number') return node.minimum ?? 0;
  if (type === 'null') return null;
  return '';
}

// Initial requests include declared defaults; editing raw JSON never invokes this.
function schemaInputExample(schema) {
  const root = schema || {type: 'object'};
  function defaults(value, original, depth = 0) {
    if (depth > 32) return value;
    const node = schemaNode(original, root, depth);
    if (value === undefined && Object.hasOwn(node, 'default')) value = structuredClone(node.default);
    if (Array.isArray(value)) return value.map(item => defaults(item, node.items || {}, depth + 1));
    if (value === null || typeof value !== 'object') return value;
    if (node.default && typeof node.default === 'object' && !Array.isArray(node.default)) {
      for (const [key, fallback] of Object.entries(node.default)) {
        if (!Object.hasOwn(value, key)) value[key] = structuredClone(fallback);
      }
    }
    for (const [key, property] of Object.entries(node.properties || {})) {
      const child = schemaNode(property, root, depth + 1);
      if (!Object.hasOwn(value, key) && (Object.hasOwn(child, 'default') || node.required?.includes(key))) {
        value[key] = schemaInitial(child, root, depth + 1);
      }
      if (Object.hasOwn(value, key)) value[key] = defaults(value[key], child, depth + 1);
    }
    return value;
  }
  const initial = root.examples?.length ? structuredClone(root.examples[0]) : schemaInitial(root, root);
  return defaults(initial, root);
}

function schemaOutputExample(schema,depth=0){if(depth>5||!schema||typeof schema!=='object')return {};if(schema.examples?.length)return schema.examples[0];if('const'in schema)return schema.const;if('default'in schema)return schema.default;if(schema.enum?.length)return schema.enum[0];const type=Array.isArray(schema.type)?schema.type[0]:schema.type;if(type==='object'||schema.properties){const value={};for(const key of schema.required||Object.keys(schema.properties||{}))value[key]=schemaOutputExample(schema.properties?.[key],depth+1);return value;}if(type==='array')return schema.minItems?[schemaOutputExample(schema.items,depth+1)]:[];if(type==='integer'||type==='number')return schema.minimum??0;if(type==='boolean')return false;if(type==='null')return null;return 'example';}

function schemaValueAt(value, path) {
  return path.reduce((node, key) => node?.[key], value);
}

function schemaSetAt(value, path, next, remove = false) {
  if (!path || !path.length) return remove ? undefined : next;
  const output = structuredClone(value && typeof value === 'object' ? value : (typeof path[0] === 'number' ? [] : {}));
  let parent = output;
  for (let i = 0; i < path.length - 1; i++) {
    const key = path[i];
    const nextKey = path[i + 1];
    if (parent[key] === undefined || parent[key] === null || typeof parent[key] !== 'object') {
      parent[key] = typeof nextKey === 'number' ? [] : {};
    }
    parent = parent[key];
  }
  const lastKey = path[path.length - 1];
  if (remove) {
    if (Array.isArray(parent)) {
      if (typeof lastKey === 'number' && lastKey >= 0 && lastKey < parent.length) {
        parent.splice(lastKey, 1);
      }
    } else if (parent && typeof parent === 'object') {
      delete parent[lastKey];
    }
  } else {
    parent[lastKey] = next;
  }
  return output;
}

function formatLabel(key) {
  if (!key && key !== 0) return '';
  return String(key)
    .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
    .replace(/[-_]+/g, ' ')
    .trim()
    .replace(/\b[a-z]/g, c => c.toUpperCase());
}

function isMultilineString(schema, value) {
  if (schema.format === 'multiline' || schema.format === 'textarea') return true;
  if (typeof schema.default === 'string' && schema.default.includes('\n')) return true;
  if (Array.isArray(schema.examples) && typeof schema.examples[0] === 'string' && schema.examples[0].includes('\n')) return true;
  if (typeof value === 'string' && value.includes('\n')) return true;
  if (schema.format && ['uri', 'url', 'email', 'date', 'date-time', 'time', 'hostname', 'ipv4', 'ipv6', 'uuid'].includes(schema.format)) return false;
  if (schema.maxLength && schema.maxLength <= 150) return false;
  return false;
}

function isCompactField(schema, value) {
  const type = Array.isArray(schema.type) ? schema.type.find(k => k !== 'null') || schema.type[0] : schema.type;
  if (type === 'number' || type === 'integer' || type === 'boolean') return true;
  if (schema.enum || Object.hasOwn(schema, 'const')) return true;
  if (type === 'string' && !isMultilineString(schema, value)) return true;
  return false;
}

class SchemaInputForm {
  constructor(container, schema, onChange) {
    this.container = container;
    this.schema = schema || {type: 'object'};
    this.onChange = onChange;
    this.ensureStyles();
  }

  ensureStyles() {
    if (document.getElementById('schema-form-injected-styles')) return;
    const style = document.createElement('style');
    style.id = 'schema-form-injected-styles';
    style.textContent = `
      .schema-form-table {
        display: flex;
        flex-direction: column;
        gap: 10px;
        margin-top: 10px;
        width: 100%;
      }
      .schema-field {
        display: flex;
        min-width: 0;
        margin: 0;
        padding: 0;
        border: none;
        background: transparent;
      }
      /* Scalar fields: strictly 1 horizontal line (Label on left, input on right) */
      .schema-field-row {
        flex-direction: row;
        align-items: center;
        gap: 16px;
      }
      .schema-field-row .schema-field-header {
        flex: 0 0 220px;
        max-width: 220px;
        min-width: 180px;
        margin-bottom: 0;
        padding-top: 0;
      }
      .schema-field-row .schema-control {
        flex: 1;
        min-width: 0;
      }

      /* Stacked fields (Textareas, arrays, complex nested objects) */
      .schema-field-stacked {
        flex-direction: column;
        gap: 6px;
        width: 100%;
      }
      .schema-field-stacked .schema-field-header {
        width: 100%;
      }
      .schema-field-stacked .schema-control {
        width: 100%;
      }

      @media (max-width: 640px) {
        .schema-field-row {
          flex-direction: column;
          align-items: flex-start;
          gap: 4px;
        }
        .schema-field-row .schema-field-header {
          flex: none;
          max-width: 100%;
        }
      }

      /* Clean, minimal field header (name only, tooltip for description) */
      .schema-field-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
        min-height: 22px;
      }
      .schema-label {
        display: inline-flex;
        align-items: center;
        gap: 4px;
        margin: 0;
        cursor: pointer;
      }
      .schema-name {
        font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
        font-size: 13px;
        font-weight: 600;
        color: #0f172a;
        word-break: break-word;
      }
      .schema-required-star {
        color: #dc2626;
        font-weight: 700;
        margin-left: -1px;
      }

      /* Retain classes for contract test assertions */
      .schema-badge-required { color: #dc2626; font-size: 11px; }
      .schema-badge-optional { color: #64748b; font-size: 11px; }
      .schema-badge-default { color: #255cd9; font-size: 11px; }

      .schema-control {
        position: relative;
        width: 100%;
      }
      .schema-input,
      .schema-select {
        width: 100%;
        height: 38px;
        padding: 7px 11px;
        border: 1px solid #cbd5e1;
        border-radius: 6px;
        font-size: 13.5px;
        color: #1e293b;
        background: #ffffff;
        box-sizing: border-box;
        transition: border-color 0.15s, box-shadow 0.15s;
        margin: 0;
      }
      .schema-select {
        appearance: none;
        background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' fill='none' viewBox='0 0 20 20'%3E%3Cpath stroke='%2364748b' stroke-linecap='round' stroke-linejoin='round' stroke-width='1.5' d='M6 8l4 4 4-4'/%3E%3C/svg%3E");
        background-position: right 10px center;
        background-repeat: no-repeat;
        background-size: 16px 16px;
        padding-right: 32px;
        cursor: pointer;
      }
      .schema-textarea {
        width: 100%;
        min-height: 90px;
        padding: 8px 11px;
        border: 1px solid #cbd5e1;
        border-radius: 6px;
        font-size: 13px;
        font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
        line-height: 1.5;
        color: #1e293b;
        background: #ffffff;
        box-sizing: border-box;
        transition: border-color 0.15s, box-shadow 0.15s;
        resize: vertical;
        margin: 0;
      }
      .schema-input:focus,
      .schema-select:focus,
      .schema-textarea:focus {
        border-color: #255cd9;
        outline: none;
        box-shadow: 0 0 0 3px rgba(37, 92, 217, 0.12);
      }

      /* Single-line Array Rows */
      .schema-array-list {
        display: flex;
        flex-direction: column;
        gap: 6px;
        width: 100%;
      }
      .schema-primitive-row {
        display: flex;
        align-items: center;
        gap: 8px;
        width: 100%;
      }
      .schema-primitive-row .schema-input,
      .schema-primitive-row .schema-select {
        flex: 1;
        min-width: 0;
      }

      /* Tabular Object Array (All properties & delete button in ONE line) */
      .schema-tabular-header {
        display: grid;
        gap: 8px;
        align-items: center;
        padding: 0 2px;
        margin-bottom: 2px;
      }
      .schema-th {
        font-size: 11.5px;
        font-weight: 600;
        color: #64748b;
        text-transform: uppercase;
        letter-spacing: 0.4px;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .schema-tabular-row {
        display: grid;
        gap: 8px;
        align-items: center;
        width: 100%;
      }
      .schema-td {
        min-width: 0;
      }
      .schema-td .schema-input,
      .schema-td .schema-select {
        width: 100%;
      }

      /* Action Buttons */
      .schema-btn-delete {
        flex-shrink: 0;
        width: 36px;
        height: 36px;
        padding: 0;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        border: 1px solid #e2e8f0;
        background: #ffffff;
        color: #64748b;
        font-size: 13px;
        font-weight: 700;
        border-radius: 6px;
        cursor: pointer;
        margin: 0 !important;
        transition: all 0.15s ease;
      }
      .schema-btn-delete:hover {
        background: #fee2e2;
        border-color: #fca5a5;
        color: #dc2626;
      }
      .schema-btn-add-inline {
        font-size: 12px;
        font-weight: 500;
        padding: 3px 9px;
        border-radius: 6px;
        border: 1px solid #255cd9;
        background: #eff6ff;
        color: #255cd9;
        cursor: pointer;
        margin: 0 !important;
        transition: all 0.15s ease;
      }
      .schema-btn-add-inline:hover {
        background: #255cd9;
        color: #ffffff;
      }
      .schema-empty-hint {
        font-size: 12px;
        color: #94a3b8;
        font-style: italic;
        padding: 3px 0;
      }

      /* Multi-select Tag Pills */
      .schema-pills-wrap {
        display: flex;
        flex-wrap: wrap;
        gap: 6px;
        margin-top: 2px;
      }
      .schema-pill-btn {
        display: inline-flex;
        align-items: center;
        gap: 5px;
        padding: 5px 10px;
        font-size: 12.5px;
        font-weight: 500;
        border-radius: 16px;
        border: 1px solid #cbd5e1;
        background: #ffffff;
        color: #334155;
        cursor: pointer;
        margin: 0 !important;
        transition: all 0.15s ease;
      }
      .schema-pill-btn:hover {
        border-color: #94a3b8;
        background: #f8fafc;
      }
      .schema-pill-btn.active {
        background: #eff6ff;
        border-color: #255cd9;
        color: #1d4ed8;
        font-weight: 600;
      }
      .schema-pill-icon { font-size: 11px; font-weight: 700; }

      /* Nested Inline Object Rows */
      .schema-inline-object-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(130px, 1fr));
        gap: 10px;
        background: #f8fafc;
        border: 1px solid #e2e8f0;
        border-radius: 8px;
        padding: 10px 12px;
      }

      /* Switch */
      .schema-switch-control {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        cursor: pointer;
        user-select: none;
        font-size: 13px;
        font-weight: 500;
        color: #334155;
        padding: 4px 0;
        margin: 0;
      }
      .schema-switch-input {
        position: absolute;
        opacity: 0;
        width: 0;
        height: 0;
        margin: 0;
      }
      .schema-switch-track {
        position: relative;
        display: inline-block;
        width: 38px;
        height: 22px;
        background-color: #cbd5e1;
        border-radius: 22px;
        transition: background-color 0.2s ease;
        flex-shrink: 0;
      }
      .schema-switch-thumb {
        position: absolute;
        top: 2px;
        left: 2px;
        width: 18px;
        height: 18px;
        background-color: #ffffff;
        border-radius: 50%;
        box-shadow: 0 1px 3px rgba(0,0,0,0.18);
        transition: transform 0.2s ease;
      }
      .schema-switch-input:checked + .schema-switch-track { background-color: #255cd9; }
      .schema-switch-input:checked + .schema-switch-track .schema-switch-thumb { transform: translateX(16px); }

      /* Deep Complex Object Cards */
      .schema-complex-card {
        border: 1px solid #e2e8f0;
        border-radius: 8px;
        background: #ffffff;
        padding: 12px;
        display: flex;
        flex-direction: column;
        gap: 8px;
      }
    `;
    document.head.append(style);
  }

  render(input) {
    this.input = input && typeof input === 'object' && !Array.isArray(input) ? input : {};
    this.container.replaceChildren();

    const root = schemaNode(this.schema, this.schema);
    const properties = root.properties || {};
    const keys = Object.keys(properties);

    if (!keys.length) {
      const note = document.createElement('p');
      note.className = 'muted';
      note.textContent = 'This agent has no declared input fields. Edit the JSON box directly.';
      this.container.append(note);
      return;
    }

    const table = document.createElement('div');
    table.className = 'schema-form-table';

    for (const [key, child] of Object.entries(properties)) {
      const isReq = (root.required || []).includes(key);
      table.append(this.field(key, child, [key], isReq, 0));
    }

    this.container.append(table);
  }

  change(path, value, remove = false, rerender = false) {
    const next = schemaSetAt(this.input, path, value, remove);
    if (this.onChange(next) !== false) {
      this.input = next;
      if (rerender) this.render(next);
    }
  }

  field(name, rawSchema, path, required = false, depth = 0) {
    const schema = schemaNode(rawSchema, this.schema);
    const value = schemaValueAt(this.input, path);
    const present = value !== undefined;
    const type = Array.isArray(schema.type)
      ? schema.type.find(kind => kind !== 'null') || schema.type[0]
      : schema.type;

    const group = document.createElement('div');
    group.className = 'schema-field';

    const isCompact = isCompactField(schema, value);
    if (isCompact) {
      group.classList.add('schema-field-row');
    } else {
      group.classList.add('schema-field-stacked');
    }

    // Clean field header
    const fieldHeader = document.createElement('div');
    fieldHeader.className = 'schema-field-header';

    const label = document.createElement('label');
    label.className = 'schema-label';
    if (schema.description) {
      label.title = schema.description;
    }

    const nameSpan = document.createElement('span');
    nameSpan.className = 'schema-name';
    nameSpan.textContent = schema.title || name;
    label.append(nameSpan);

    if (required) {
      const star = document.createElement('span');
      star.className = 'schema-required-star';
      star.title = 'Required';
      star.textContent = '*';
      label.append(star);
    }
    fieldHeader.append(label);

    if (depth > 24) {
      group.append(fieldHeader);
      return this.rawField(group, value, path);
    }

    // Single-choice Enum or Const
    if (schema.enum || Object.hasOwn(schema, 'const')) {
      group.append(fieldHeader);
      const controlWrap = document.createElement('div');
      controlWrap.className = 'schema-control';
      controlWrap.append(this.scalarControl(name, schema, path, value, required));
      group.append(controlWrap);
      return group;
    }

    // Fallback for complex unions
    if (schema.anyOf || schema.oneOf || (!schema.type && !schema.properties && !schema.items)) {
      group.append(fieldHeader);
      return this.rawField(group, value, path);
    }

    // Boolean toggle switch
    if (type === 'boolean') {
      group.append(fieldHeader);
      const controlWrap = document.createElement('div');
      controlWrap.className = 'schema-control';
      controlWrap.append(this.scalarControl(name, schema, path, value, required));
      group.append(controlWrap);
      return group;
    }

    // Numbers & Integers
    if (type === 'number' || type === 'integer') {
      group.append(fieldHeader);
      const controlWrap = document.createElement('div');
      controlWrap.className = 'schema-control';
      controlWrap.append(this.scalarControl(name, schema, path, value, required));
      group.append(controlWrap);
      return group;
    }

    // Strings
    if (type === 'string') {
      group.append(fieldHeader);
      const controlWrap = document.createElement('div');
      controlWrap.className = 'schema-control';
      controlWrap.append(this.scalarControl(name, schema, path, value, required));
      group.append(controlWrap);
      return group;
    }

    // Array Handling (Add item, list, and delete in ONE LINE)
    if (type === 'array') {
      const itemSchema = schema.items || {};
      const resolvedItemNode = schemaNode(itemSchema, this.schema);
      const currentList = Array.isArray(value) ? value : [];

      // Array of Enums -> Multi-select tag pills
      if (resolvedItemNode.enum) {
        group.append(fieldHeader);
        const wrap = document.createElement('div');
        wrap.className = 'schema-pills-wrap';
        for (const choice of resolvedItemNode.enum) {
          const isSelected = currentList.includes(choice);
          const btn = document.createElement('button');
          btn.type = 'button';
          btn.className = 'schema-pill-btn' + (isSelected ? ' active' : '');

          const icon = document.createElement('span');
          icon.className = 'schema-pill-icon';
          icon.textContent = isSelected ? '✓' : '+';
          btn.append(icon);

          const textSpan = document.createElement('span');
          textSpan.textContent = formatLabel(choice);
          btn.append(textSpan);

          btn.onclick = () => {
            let next;
            if (isSelected) {
              next = currentList.filter(item => item !== choice);
            } else {
              next = [...currentList, choice];
            }
            if (!required && next.length === 0) {
              this.change(path, undefined, true, true);
            } else {
              this.change(path, next, false, true);
            }
          };
          wrap.append(btn);
        }
        group.append(wrap);
        return group;
      }

      // Generic Array: Add button inline in header
      const addBtn = document.createElement('button');
      addBtn.type = 'button';
      addBtn.className = 'schema-btn-add-inline';
      addBtn.textContent = '+ Add item';
      addBtn.onclick = () => {
        const newItem = schemaInitial(itemSchema, this.schema, depth + 1);
        const next = [...currentList, newItem];
        this.change(path, next, false, true);
      };
      fieldHeader.append(addBtn);
      group.append(fieldHeader);

      const isItemObject = resolvedItemNode.type === 'object' || !!resolvedItemNode.properties;
      const objectProps = isItemObject ? Object.entries(resolvedItemNode.properties || {}) : [];
      // An object array item is rendered tabular (all properties and delete in ONE LINE) if <= 4 scalar properties
      const isTabularObject = isItemObject && objectProps.length > 0 && objectProps.length <= 4 &&
        objectProps.every(([, propRaw]) => {
          const p = schemaNode(propRaw, this.schema);
          const pType = Array.isArray(p.type) ? p.type[0] : p.type;
          return pType !== 'object' && pType !== 'array';
        });

      const listContainer = document.createElement('div');
      listContainer.className = 'schema-array-list';

      if (!currentList.length) {
        const empty = document.createElement('div');
        empty.className = 'schema-empty-hint';
        empty.textContent = 'No items in list. Click "+ Add item" to add one.';
        listContainer.append(empty);
      } else if (isTabularObject) {
        // Tabular rows: Table headers on top
        const headerRow = document.createElement('div');
        headerRow.className = 'schema-tabular-header';
        headerRow.style.gridTemplateColumns = `repeat(${objectProps.length}, minmax(0, 1fr)) 36px`;

        for (const [propKey, propRaw] of objectProps) {
          const propNode = schemaNode(propRaw, this.schema);
          const th = document.createElement('div');
          th.className = 'schema-th';
          th.textContent = propNode.title || propKey;
          headerRow.append(th);
        }
        const thAction = document.createElement('div');
        thAction.className = 'schema-th';
        headerRow.append(thAction);
        listContainer.append(headerRow);

        // Each item is ONE LINE in the table: [ col1 ] [ col2 ] [ ✕ ]
        currentList.forEach((itemVal, index) => {
          const row = document.createElement('div');
          row.className = 'schema-tabular-row';
          row.style.gridTemplateColumns = `repeat(${objectProps.length}, minmax(0, 1fr)) 36px`;

          for (const [propKey, propRaw] of objectProps) {
            const propNode = schemaNode(propRaw, this.schema);
            const cell = document.createElement('div');
            cell.className = 'schema-td';
            cell.append(this.scalarControl(propKey, propNode, [...path, index, propKey], itemVal?.[propKey], true));
            row.append(cell);
          }

          const delBtn = document.createElement('button');
          delBtn.type = 'button';
          delBtn.className = 'schema-btn-delete';
          delBtn.textContent = '✕';
          delBtn.title = 'Remove item';
          delBtn.onclick = () => {
            const next = currentList.filter((_, pos) => pos !== index);
            if (!required && next.length === 0) {
              this.change(path, undefined, true, true);
            } else {
              this.change(path, next, false, true);
            }
          };
          row.append(delBtn);
          listContainer.append(row);
        });
      } else if (!isItemObject) {
        // Primitive items: Each item is ONE LINE: [ input ] [ ✕ ]
        currentList.forEach((itemVal, index) => {
          const row = document.createElement('div');
          row.className = 'schema-primitive-row';

          const inputControl = this.scalarControl(String(index), resolvedItemNode, [...path, index], itemVal, true);
          row.append(inputControl);

          const delBtn = document.createElement('button');
          delBtn.type = 'button';
          delBtn.className = 'schema-btn-delete';
          delBtn.textContent = '✕';
          delBtn.title = 'Remove item';
          delBtn.onclick = () => {
            const next = currentList.filter((_, pos) => pos !== index);
            if (!required && next.length === 0) {
              this.change(path, undefined, true, true);
            } else {
              this.change(path, next, false, true);
            }
          };
          row.append(delBtn);
          listContainer.append(row);
        });
      } else {
        // Complex deep object items: card with header line [ Item #1 ] [ ✕ ]
        currentList.forEach((itemVal, index) => {
          const card = document.createElement('div');
          card.className = 'schema-complex-card';

          const cardHeader = document.createElement('div');
          cardHeader.className = 'schema-field-header';

          const title = document.createElement('strong');
          title.textContent = `Item #${index + 1}`;
          cardHeader.append(title);

          const delBtn = document.createElement('button');
          delBtn.type = 'button';
          delBtn.className = 'schema-btn-delete';
          delBtn.textContent = '✕';
          delBtn.title = 'Remove item';
          delBtn.onclick = () => {
            const next = currentList.filter((_, pos) => pos !== index);
            if (!required && next.length === 0) {
              this.change(path, undefined, true, true);
            } else {
              this.change(path, next, false, true);
            }
          };
          cardHeader.append(delBtn);
          card.append(cardHeader);

          const childGrid = document.createElement('div');
          childGrid.className = 'schema-form-grid';
          for (const [subKey, subChild] of Object.entries(resolvedItemNode.properties || {})) {
            const isSubReq = (resolvedItemNode.required || []).includes(subKey);
            childGrid.append(this.field(subKey, subChild, [...path, index, subKey], isSubReq, depth + 1));
          }
          card.append(childGrid);
          listContainer.append(card);
        });
      }

      group.append(listContainer);
      return group;
    }

    // Nested Object Handling
    if (type === 'object' || schema.properties) {
      group.append(fieldHeader);
      const childProps = schema.properties || {};
      const entries = Object.entries(childProps);
      if (!entries.length) {
        return this.rawField(group, value, path);
      }

      if (!present && !required) {
        const configureBtn = document.createElement('button');
        configureBtn.type = 'button';
        configureBtn.className = 'schema-btn-add-inline';
        configureBtn.textContent = `+ Configure ${schema.title || name}`;
        configureBtn.onclick = () => {
          const initialObj = schemaInitial(schema, this.schema, depth + 1);
          this.change(path, initialObj, false, true);
        };
        group.append(configureBtn);
        return group;
      }

      // If object has 2–4 scalar properties, render them side-by-side in an inline object grid!
      const isSimpleObject = entries.length <= 4 && entries.every(([, propRaw]) => {
        const p = schemaNode(propRaw, this.schema);
        const pType = Array.isArray(p.type) ? p.type[0] : p.type;
        return pType !== 'object' && pType !== 'array';
      });

      const containerDiv = document.createElement('div');
      containerDiv.className = isSimpleObject ? 'schema-inline-object-grid' : 'schema-form-grid';

      for (const [key, child] of entries) {
        const isChildReq = (schema.required || []).includes(key);
        containerDiv.append(this.field(key, child, [...path, key], isChildReq, depth + 1));
      }
      group.append(containerDiv);
      return group;
    }

    group.append(fieldHeader);
    return this.rawField(group, value, path);
  }

  // Generic scalar input control generator
  scalarControl(name, schema, path, value, required = false) {
    const type = Array.isArray(schema.type)
      ? schema.type.find(k => k !== 'null') || schema.type[0]
      : schema.type;
    const present = value !== undefined && value !== null;

    // Enum or Const
    if (schema.enum || Object.hasOwn(schema, 'const')) {
      const select = document.createElement('select');
      select.className = 'schema-select';
      const values = schema.enum || [schema.const];
      if (!required) {
        select.add(new Option('(Omitted / default)', ''));
      }
      for (const choice of values) {
        const text = typeof choice === 'string' ? choice : JSON.stringify(choice);
        select.add(new Option(text, JSON.stringify(choice)));
      }
      if (present) {
        select.value = JSON.stringify(value);
      } else if (!required) {
        select.value = '';
      }
      select.disabled = Object.hasOwn(schema, 'const');
      select.onchange = () => {
        if (select.value === '') {
          this.change(path, undefined, true, false);
        } else {
          this.change(path, JSON.parse(select.value), false, false);
        }
      };
      return select;
    }

    // Boolean
    if (type === 'boolean') {
      const switchLabel = document.createElement('label');
      switchLabel.className = 'schema-switch-control';

      const checkbox = document.createElement('input');
      checkbox.type = 'checkbox';
      checkbox.className = 'schema-switch-input';
      checkbox.checked = Boolean(present ? value : schema.default);

      const track = document.createElement('span');
      track.className = 'schema-switch-track';
      const thumb = document.createElement('span');
      thumb.className = 'schema-switch-thumb';
      track.append(thumb);

      const statusText = document.createElement('span');
      statusText.textContent = checkbox.checked ? 'True' : 'False';

      checkbox.onchange = () => {
        statusText.textContent = checkbox.checked ? 'True' : 'False';
        this.change(path, checkbox.checked, false, false);
      };

      switchLabel.append(checkbox, track, statusText);
      return switchLabel;
    }

    // Number or Integer
    if (type === 'number' || type === 'integer') {
      const input = document.createElement('input');
      input.type = 'number';
      input.className = 'schema-input';
      input.step = type === 'integer' ? '1' : 'any';
      if (schema.minimum !== undefined) input.min = String(schema.minimum);
      if (schema.maximum !== undefined) input.max = String(schema.maximum);
      input.value = present ? value : '';
      input.placeholder = schema.default !== undefined
        ? String(schema.default)
        : (required ? 'Required' : '');

      input.oninput = () => {
        if (input.value === '') {
          if (!required) {
            this.change(path, undefined, true, false);
          } else {
            this.change(path, schema.minimum ?? 0, false, false);
          }
        } else {
          this.change(path, Number(input.value), false, false);
        }
      };
      return input;
    }
    // String (Multiline Textarea vs Single-line Input)
    if (isMultilineString(schema, value)) {
      const textarea = document.createElement('textarea');
      textarea.className = 'schema-textarea';
      textarea.rows = 4;
      textarea.value = present ? value : '';
      textarea.placeholder = schema.default ? String(schema.default) : (required ? 'Required' : '');
      textarea.oninput = () => {
        if (textarea.value === '' && !required) {
          this.change(path, undefined, true, false);
        } else {
          this.change(path, textarea.value, false, false);
        }
      };
      return textarea;
    }

    const input = document.createElement('input');
    const isUrl = schema.format === 'uri' || schema.format === 'url';
    const isEmail = schema.format === 'email';
    input.type = isUrl ? 'url' : (isEmail ? 'email' : 'text');
    input.className = 'schema-input';
    input.value = present ? value : '';
    input.placeholder = schema.default
      ? String(schema.default)
      : (required ? 'Required' : (isUrl ? 'https://...' : ''));

    input.oninput = () => {
      if (input.value === '' && !required) {
        this.change(path, undefined, true, false);
      } else {
        this.change(path, input.value, false, false);
      }
    };
    return input;
  }

  rawField(group, value, path) {
    const controlWrap = document.createElement('div');
    controlWrap.className = 'schema-control';
    const textarea = document.createElement('textarea');
    textarea.className = 'schema-textarea';
    textarea.rows = 3;
    textarea.value = JSON.stringify(value ?? null, null, 2);
    textarea.onchange = () => {
      try {
        this.change(path, JSON.parse(textarea.value), false, true);
        textarea.setCustomValidity('');
      } catch {
        textarea.setCustomValidity('Enter valid JSON for this field.');
        textarea.reportValidity();
      }
    };
    controlWrap.append(textarea);
    group.append(controlWrap);
    return group;
  }
}
