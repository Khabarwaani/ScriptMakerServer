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
function schemaValueAt(value, path) {
  return path.reduce((node, key) => node?.[key], value);
}
function schemaSetAt(value, path, next, remove = false) {
  const output = structuredClone(value);
  let parent = output;
  for (const key of path.slice(0, -1)) parent = parent[key];
  const key = path.at(-1);
  if (remove) {
    if (Array.isArray(parent)) parent.splice(key, 1);
    else delete parent[key];
  } else parent[key] = next;
  return output;
}
class SchemaInputForm {
  constructor(container, schema, onChange) {
    this.container = container;
    this.schema = schema || {type: 'object'};
    this.onChange = onChange;
  }
  render(input) {
    this.input = input && typeof input === 'object' && !Array.isArray(input) ? input : {};
    this.container.replaceChildren();
    const root = schemaNode(this.schema, this.schema);
    for (const [key, child] of Object.entries(root.properties || {})) {
      this.container.append(this.field(key, child, [key], (root.required || []).includes(key)));
    }
    if (!Object.keys(root.properties || {}).length) {
      const note = document.createElement('p'); note.className = 'muted';
      note.textContent = 'This agent has no declared input fields. Edit the JSON box directly.';
      this.container.append(note);
    }
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
    const group = document.createElement('div'); group.className = 'schema-field';
    const label = document.createElement('label'); label.textContent = name + (required ? ' (required)' : ' (optional)');
    group.append(label);
    if (schema.description) {
      const hint = document.createElement('small'); hint.className = 'muted'; hint.textContent = schema.description; group.append(hint);
    }
    if (!required) {
      const toggle = document.createElement('label'); toggle.className = 'schema-include';
      const checkbox = document.createElement('input'); checkbox.type = 'checkbox'; checkbox.checked = present;
      checkbox.onchange = () => this.change(path, schemaInitial(schema, this.schema), !checkbox.checked, true);
      toggle.append(checkbox, document.createTextNode('Include in request')); group.append(toggle);
    }
    if (!present && !required) return group;
    if (depth > 24) return this.rawField(group, value, path);
    if (schema.enum || Object.hasOwn(schema, 'const')) {
      const select = document.createElement('select');
      const values = schema.enum || [schema.const];
      for (const choice of values) {
        const option = new Option(typeof choice === 'string' ? choice : JSON.stringify(choice), JSON.stringify(choice)); select.add(option);
      }
      select.value = JSON.stringify(value);
      select.disabled = Object.hasOwn(schema, 'const');
      select.onchange = () => this.change(path, JSON.parse(select.value));
      group.append(select); return group;
    }
    if (schema.anyOf || schema.oneOf || !schema.type && !schema.properties && !schema.items) return this.rawField(group, value, path);
    const type = Array.isArray(schema.type) ? schema.type.find(kind => kind !== 'null') || schema.type[0] : schema.type;
    if (type === 'object' || schema.properties) {
      const children = document.createElement('div'); children.className = 'schema-children';
      for (const [key, child] of Object.entries(schema.properties || {})) {
        children.append(this.field(key, child, [...path, key], (schema.required || []).includes(key), depth + 1));
      }
      if (!Object.keys(schema.properties || {}).length) this.rawField(children, value, path);
      group.append(children); return group;
    }
    if (type === 'array') {
      const entries = Array.isArray(value) ? value : [];
      entries.forEach((item, index) => {
        const row = document.createElement('div'); row.className = 'schema-array-item';
        const itemSchema = schema.prefixItems?.[index] || schema.items || {};
        row.append(this.field(`Item ${index + 1}`, itemSchema, [...path, index], true, depth + 1));
        const remove = document.createElement('button'); remove.type = 'button'; remove.className = 'secondary';
        remove.textContent = `Remove item ${index + 1}`;
        remove.onclick = () => this.change(path, entries.filter((_, position) => position !== index), false, true);
        row.append(remove); group.append(row);
      });
      const add = document.createElement('button'); add.type = 'button'; add.className = 'secondary'; add.textContent = 'Add item';
      add.onclick = () => this.change(path, [...entries, schemaInitial(schema.items || {}, this.schema)], false, true);
      group.append(add); return group;
    }
    if (type === 'boolean') {
      const select = document.createElement('select');
      select.add(new Option('True', 'true')); select.add(new Option('False', 'false'));
      select.value = String(value);
      select.onchange = () => this.change(path, select.value === 'true');
      group.append(select); return group;
    }
    if (type === 'null') return this.rawField(group, value, path);
    if (type === 'number' || type === 'integer') {
      const input = document.createElement('input'); input.type = 'number'; input.step = type === 'integer' ? '1' : 'any';
      if (schema.minimum !== undefined) input.min = String(schema.minimum);
      if (schema.maximum !== undefined) input.max = String(schema.maximum);
      input.value = value ?? '';
      input.oninput = () => this.change(path, input.value === '' ? '' : Number(input.value));
      group.append(input); return group;
    }
    const textarea = document.createElement('textarea'); textarea.rows = 3; textarea.value = value ?? '';
    textarea.oninput = () => this.change(path, textarea.value);
    group.append(textarea); return group;
  }
  rawField(group, value, path) {
    const textarea = document.createElement('textarea'); textarea.rows = 3; textarea.value = JSON.stringify(value ?? null, null, 2);
    textarea.onchange = () => {
      try { this.change(path, JSON.parse(textarea.value), false, true); textarea.setCustomValidity(''); }
      catch { textarea.setCustomValidity('Enter valid JSON for this field.'); textarea.reportValidity(); }
    };
    group.append(textarea); return group;
  }
}
