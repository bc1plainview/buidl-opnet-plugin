# Knowledge Slice Template
#
# Use this template to generate domain-specific knowledge for dynamically created agents.
# Knowledge slices provide agents with project-specific context they need to do their job well.
#
# Generated slices are written to: .claude/loop/sessions/<name>/knowledge/<domain>.md

# [DOMAIN_NAME] Knowledge

## Overview

[BRIEF_DESCRIPTION of what this domain covers in the project]

## Architecture

[KEY_ARCHITECTURE_DECISIONS relevant to this domain]
- Component relationships
- Data flow patterns
- Integration points with other domains

## Conventions

[PROJECT_CONVENTIONS for this domain]
- File naming patterns
- Code organization
- Import/export patterns
- Error handling approach

## Key Files

| File | Purpose |
|------|---------|
| [FILE_PATH] | [DESCRIPTION] |

## Dependencies

[EXTERNAL_DEPENDENCIES this domain relies on]
- Libraries and their versions
- External services
- Internal modules from other domains

## Constraints

[HARD_CONSTRAINTS that must be followed]
- Performance requirements
- Security boundaries
- API contracts
- Compatibility requirements

## Common Patterns

[CODE_PATTERNS used in this domain]

```
[EXAMPLE_PATTERN]
```

## Pitfalls

[KNOWN_PITFALLS and how to avoid them]
- [PITFALL_1]: [DESCRIPTION] → [MITIGATION]
- [PITFALL_2]: [DESCRIPTION] → [MITIGATION]

## Testing

[TESTING_APPROACH for this domain]
- Test framework and location
- Test naming convention
- What to test vs what to skip
- How to run tests
