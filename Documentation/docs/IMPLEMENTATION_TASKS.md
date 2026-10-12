# Implementation tasks

## Compile-time agent package registration and package-backed discovery

Status: completed.

Every executable agent and version must be declared by an explicitly registered,
linked Swift subpackage. Having a directory and its own `Package.swift` is
insufficient for availability. Package declarations and packaged resources must be
the source of truth for execution, discovery, help and API documentation.

Required changes:

- Add local package dependencies for `NewsResearcher` and `ScriptWriter` to
  `Packages/AgentServer/Package.swift`, and link their library products to the
  appropriate server target.
- Ensure the Xcode workspace resolves and builds the registered agent packages
  as actual package dependencies, rather than showing only ordinary folders.
- Define a shared typed Swift agent-package contract. Each package must expose
  its agent ID, explicitly declared available versions, role, instructions,
  optional input schema and required output schema through that contract and its
  SwiftPM resource bundle. Keep provider-specific behavior outside these packages.
- Introduce explicit Swift registration of linked packages. Use the typed contract
  to catch missing or incompatible package implementations at compile time.
- Discover versions from package declarations, not filesystem directory scans.
  Directory names or copied resources alone must not register an agent or version.
- Require package and version registration plus valid definition resources before making an
  agent version available. An unregistered directory must be treated as invalid,
  excluded from `GET /agents`, and rejected by `POST /execute` with a structured
  `invalid_agent_definition` error.
- Make `GET /agents`, execution/version resolution, help pages, dropdowns,
  OpenAPI schemas/examples and Try pages consume the same package-backed registry.
  Do not maintain separate hardcoded agent metadata in the server or web pages.
- Generate a README document for every agent package as part of the Swift build.
  Use a Swift build-time generator compatible with SwiftPM and the Xcode build;
  do not generate it lazily during HTTP requests.
- Generate documentation from the same authoritative package declarations and
  resources used to produce the typed agent contract. Include agent responsibility,
  declared versions, version-specific instructions, input/output schemas, examples,
  constraints and package-authored notes. Keep authored notes within the agent
  package and validate their declared resource references during the build.
- Package the generated README and documentation metadata with the built agent
  so help pages and other consumers can read them through the package contract.
  Generate artifacts in designated build output rather than modifying tracked
  source files during a normal build.
- Make agent-specific help sections and related documentation refer to the
  generated package README and its versioned contract sections. Preserve the
  HTTP-only purpose of the server's API help: server startup and implementation
  instructions belong in developer documentation, not consumer-facing API help.
- Keep generated documentation deterministic and ensure links, examples and
  version labels match the built package. Clearly label illustrative output
  examples so they cannot be mistaken for actual execution results.
- Keep multiple declared immutable versions independently available and retain
  exact-version selection and highest-stable default resolution.
- Adding an agent or version requires updating its package declarations,
  registration where applicable, and rebuilding. Unbuilt or undeclared additions
  must remain unavailable. This supersedes the earlier task's runtime discovery
  requirement for newly added Markdown versions.
- Add mandatory build checks for resource completeness, semantic versions and
  schema validity. Swift compilation checks interfaces and types; it does not
  automatically prove that arbitrary Markdown or JSON resource contents are valid.
- Validate every declared output schema and optional input schema during the build,
  before generating documentation and making the agent package available. Invalid
  JSON, malformed schema structure, unsupported assertions, unresolved references
  or missing schema resources must fail the SwiftPM and Xcode builds with clear
  diagnostics identifying the agent, version, file and failing schema location.
- Run these checks through the required Swift build-time generator/validation step,
  not only through an optional developer command or test suite. The supported schema
  dialect and assertions must match the server's runtime validator. Validate declared
  documentation examples against their corresponding schemas during the same step.
- Make agent validation and documentation generation required dependencies of the
  server compilation/build graph. Normal Debug, Release, SwiftPM, Xcode and CI builds
  must run them automatically when their inputs change; no separate manual command
  may be required to obtain a validated runnable server.
- Emit build-generated validation metadata identifying the checked agent versions
  and schema resources. The running server must register only those built, validated
  versions and must reject missing, unvalidated or changed schema resources. Verify
  that packaged resources match their validation metadata before exposing them;
  do not fall back to unchecked filesystem discovery.
- Retain runtime validation of client input when an input schema is defined and of
  every final provider result. Build-time schema validation checks the contract itself;
  it does not establish that future execution data conforms to that contract.
- Update `AgentTools check` to report missing registration and document the complete
  create, register, build and validate workflow.

Acceptance checks:

- Both existing agents appear as linked Swift package dependencies in Xcode and
  are available through the registry when their definitions are valid.
- A complete agent directory without package registration is unavailable and
  produces the required execution error.
- A registered package with incomplete or invalid definition files is unavailable.
- Versions appear only when declared and included by the built linked package.
- Help, API documentation, dropdowns and execution expose the same package-defined
  versions and contracts, including after a package version is added and rebuilt.
- A clean SwiftPM or Xcode build generates each agent's README and makes it
  available through the built package; no HTTP request is needed for generation.
- Agent help displays the generated README's current versioned formats and notes.
  Changes to package declarations or authored notes are reflected after rebuilding,
  with no separate manual edits to server-side agent documentation.
- Missing or incompatible typed package implementations fail compilation; missing
  resources, invalid semantic versions or invalid schemas fail required build checks.
- A clean SwiftPM or Xcode build fails for malformed schema JSON, invalid schema
  structure, unsupported constraints, unresolved references or invalid examples.
  These failures occur without starting the HTTP server or making provider calls.
- Incremental builds rerun validation after schema, example or version-declaration
  changes. Server compilation depends on successful validation, and the running
  server cannot expose an agent version without matching build-generated validation
  metadata.
- Deterministic Swift tests cover registration, rejection, version discovery and
  package build integration.

This task is implemented and verified: package-backed discovery, build-time validation, build-generated documentation, and metadata verification are enforced.
