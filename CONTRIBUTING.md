# Contributing to proxmox-playground

Thank you for interest in contributing! This guide explains how to add new scripts and collections to this repository.

## Repository Structure

```
proxmox-playground/
├── README.md                    # Main repository overview
├── CONTRIBUTING.md              # This file
├── docs/                        # Root documentation
│   ├── FILE_INDEX.md
│   └── PROJECT_SUMMARY.md
└── <collection-name>/           # Script collections
    ├── README.md
    ├── scripts/                 # Executable scripts
    ├── examples/                # Configuration templates
    └── docs/                    # Collection documentation
```

## Adding New Collections

### 1. Create Directory Structure

```bash
mkdir -p my-collection/{scripts,examples,docs}
```

### 2. Create Scripts

Place all executable bash scripts in `scripts/`:

```bash
#!/bin/bash
################################################################################
# Script Name - Brief Description
# 
# Purpose: What this script does
# Usage: How to use it
################################################################################

set -euo pipefail

# Color output (optional but recommended)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
print_success() { echo -e "${GREEN}[✓]${NC} $*"; }
print_error() { echo -e "${RED}[✗]${NC} $*" >&2; }

# ... your script content ...
```

### 3. Create Examples

Place configuration templates and examples in `examples/`:

```
examples/
├── config-template.conf
├── setup-example.sh
└── README.md                    # Explain examples
```

### 4. Create Documentation

Place documentation in `docs/`:

```
docs/
├── GUIDE.md                     # Comprehensive guide
├── QUICK_REFERENCE.md           # Quick commands
├── TROUBLESHOOTING.md           # Common issues
└── ARCHITECTURE.md              # Design overview
```

### 5. Create Collection README

Create `my-collection/README.md`:

```markdown
# my-collection

Brief description of what this collection does.

## Quick Start

Show how to get started quickly.

## Scripts

List and describe each script.

## Examples

Explain the example configurations.

## Documentation

Link to detailed documentation.

## Requirements

List what's needed to use these scripts.
```

### 6. Update Root README

Update the main `README.md` with:
- New collection in 📁 Repository Structure
- New collection in 🎯 Collections section
- New collection in 🎯 Common Tasks section (if applicable)

## Script Guidelines

### Bash Standards

- Use `#!/bin/bash` shebang
- Enable strict mode: `set -euo pipefail`
- Add comprehensive comments
- Use meaningful variable names
- Include inline documentation

### Features to Include

✅ **Help/Usage**
```bash
print_usage() {
    cat << EOF
Usage: ./script.sh [options]
...
EOF
    exit 1
}
```

✅ **Dry-Run Mode** (when modifying system)
```bash
if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY-RUN] Would execute: command"
else
    command
fi
```

✅ **Verbose Output** (for debugging)
```bash
verbose() {
    if [[ "$VERBOSE" == true ]]; then
        echo "[VERBOSE] $*"
    fi
}
```

✅ **Error Handling**
```bash
if ! command; then
    print_error "Command failed"
    exit 1
fi
```

✅ **Root Check** (when needed)
```bash
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root"
    exit 1
fi
```

✅ **Parameter Validation**
```bash
if [[ -z "$VARIABLE" ]]; then
    print_error "Variable is required"
    exit 1
fi
```

### Style Recommendations

- Use lowercase with underscores for variables
- Use UPPERCASE for constants
- Keep lines under 100 characters where possible
- Use functions for repeated code
- Add comments for complex logic
- Include examples in help text

### Documentation in Scripts

```bash
################################################################################
# Function: do_something
#
# Description: What this function does
#
# Arguments:
#   $1 - First argument description
#   $2 - Second argument description
#
# Returns:
#   0 on success, 1 on failure
#
# Example:
#   do_something "arg1" "arg2"
#
################################################################################

do_something() {
    local arg1="$1"
    local arg2="$2"
    
    # Implementation...
}
```

## Documentation Standards

### README Files

Each collection's README should include:

1. **Title and Description**
   - What does this collection do?
   - Why would someone use it?

2. **Quick Start**
   - 2-3 simple examples
   - Copy-paste ready commands

3. **Directory Structure**
   - Show the folder layout
   - Explain what's in each directory

4. **Scripts Section**
   - Name, purpose, and usage of each script
   - Command-line options
   - Examples

5. **Key Features**
   - Bulleted list of important features
   - Safety features highlighted

6. **Requirements**
   - Prerequisites and dependencies
   - ProxMox version
   - System requirements

7. **FAQ**
   - Common questions
   - Common problems

8. **Documentation Links**
   - Links to detailed guides
   - Quick reference links

### Guide Documents

Use Markdown format with:

- Clear headings (using `#`, `##`, `###`)
- Code blocks with language tags
- Examples with explanations
- Troubleshooting sections
- Warning/Note callouts

```markdown
# My Guide

## Section

Explanation text.

### Subsection

```bash
# Code example
command
```

> **Note**: Important information

> **Warning**: Potential issues
```

## Testing

Before submitting:

1. **Test on ProxMox**
   - Run scripts on an actual ProxMox host
   - Test both normal and error cases
   - Verify dry-run mode works

2. **Test Documentation**
   - Follow the quick start guide
   - Verify all links work
   - Check code examples for accuracy

3. **Code Review**
   - Read your own code
   - Check for typos
   - Verify error handling

4. **Safety Check**
   - Does it have safety features?
   - Does it prompt before destructive actions?
   - Does dry-run mode work?

## Commit Messages

Use clear, descriptive commit messages:

```
[collection-name] Brief description of change

Optional longer explanation if needed.

- Bullet point 1
- Bullet point 2
```

Examples:
```
[docker-zvol] Add support for quota management
[docker-zvol] Fix permission handling for unprivileged containers
[docs] Update CONTRIBUTING guide
```

## Pull Request Process

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Make your changes
4. Test thoroughly
5. Commit with clear messages
6. Push to your fork
7. Create a Pull Request with description

## Code Review Checklist

Your submission should include:

- [ ] Script(s) following bash guidelines
- [ ] Dry-run mode (if modifying system)
- [ ] Input validation
- [ ] Error handling
- [ ] Help/usage information
- [ ] README.md for collection
- [ ] Documentation in docs/
- [ ] Examples in examples/
- [ ] .gitignore updated if needed
- [ ] Root README.md updated

## Questions or Issues?

- Check existing documentation
- Review similar scripts for patterns
- Look at the git history
- Ask in the repository issues

## Collection Checklist

When adding a new collection, ensure:

- [ ] Directory structure created (`scripts/`, `examples/`, `docs/`)
- [ ] All scripts are executable (`chmod +x script.sh`)
- [ ] README.md created with quick start
- [ ] All scripts have help/usage information
- [ ] Examples provided
- [ ] Documentation created
- [ ] Root README.md updated
- [ ] .gitignore updated if needed
- [ ] Scripts tested on ProxMox
- [ ] Documentation links verified

## Best Practices

1. **Keep it Simple**
   - One script = one clear purpose
   - Don't try to do everything in one script

2. **Make it Safe**
   - Always include validation
   - Prompt before destructive actions
   - Support dry-run mode

3. **Make it Discoverable**
   - Clear naming (descriptive filenames)
   - Comprehensive documentation
   - Good examples

4. **Make it Maintainable**
   - Write for others to understand
   - Add comments for complex logic
   - Use consistent style

5. **Make it Helpful**
   - Provide good error messages
   - Include examples
   - Document edge cases

## Directory Naming

- Use lowercase with hyphens: `my-collection`, not `MyCollection`
- Be descriptive: `docker-zvol` not `docker`
- Avoid single letters or abbreviations

## File Naming

- Scripts: descriptive names like `setup-docker-zvol.sh`
- Examples: `config-template.conf` or `example-setup.sh`
- Docs: `GUIDE.md`, `QUICK_REFERENCE.md`, `TROUBLESHOOTING.md`

## Questions?

- Check the root README.md
- Review existing collections
- Look at git history for examples

Thank you for contributing to make ProxMox administration easier! 🚀
