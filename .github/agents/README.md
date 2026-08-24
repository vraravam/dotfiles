# Dotfiles Repository Agents

Custom agents for reviewing and improving shell and Ruby scripts in this dotfiles repository.

## Overview

These agents are specialized reviewers that understand the dotfiles repository's coding standards (defined in `.ai/domains/`). They provide structured feedback aligned with repository patterns.

**Important**: These agents provide REVIEW and RECOMMENDATIONS only. They do NOT edit files directly. You must apply suggested changes manually.

## Available Agents

### 1. Shell Script Reviewer
**File**: `shell-script-reviewer.agent.md`
**Invoke**: See usage section below

**Purpose**: Reviews shell scripts (`.sh`, `.zsh`, `.bash`, `.shellrc`, `.aliases`, autoload functions) for correctness, style, performance, and adherence to `.ai/domains/shell-scripting.md`.

**When to use**:
- After creating or editing any shell script
- Before committing shell script changes
- When refactoring shell functions
- When optimizing startup scripts (`.zshrc`, `.shellrc`)
- When debugging shell script issues

**Output**: Structured review with line numbers, categorized by severity (Critical/Style/Performance/Security), specific recommendations, and adherence checklist.

---

### 2. Ruby Script Reviewer
**File**: `ruby-script-reviewer.agent.md`
**Invoke**: See usage section below

**Purpose**: Reviews Ruby scripts (`.rb` files) for correctness, Ruby 2.6 compatibility, style, performance, and adherence to `.ai/domains/ruby-scripting.md`.

**When to use**:
- After creating or editing any Ruby script
- Before committing Ruby script changes
- When refactoring Ruby methods
- When converting shell scripts to Ruby
- When debugging Ruby 2.6 compatibility issues

**Output**: Structured review with line numbers, categorized by severity (Critical/Ruby 2.6 Compatibility/Style/Performance/Security), dual-mode pattern compliance check, and adherence checklist.

---

### 3. Security Reviewer
**File**: `security-reviewer.agent.md`
**Invoke**: See usage section below

**Purpose**: Reviews shell and Ruby scripts for security vulnerabilities including command injection, unsafe file operations, credential exposure, and privilege escalation.

**When to use**:
- After any script changes involving system calls
- Before committing scripts that use `sudo`, `rm`, `chmod`
- When handling user input or environment variables
- When dealing with credentials or sensitive data
- Before deploying fresh-install scripts

**Output**: Risk-rated findings (CRITICAL/HIGH/MEDIUM/LOW) with exploit scenarios, remediation steps, and overall risk assessment.

---

## Usage

These agents are designed to work with GitHub Copilot Chat. To use them:

### Option 1: Reference Agent File Directly

```
Please review this file using the shell-script-reviewer agent:
[Paste path: .github/agents/shell-script-reviewer.agent.md]

File to review: scripts/fresh-install-of-osx.sh
```

### Option 2: Provide Agent Instructions Inline

```
Act as the shell-script-reviewer agent (see .github/agents/shell-script-reviewer.agent.md).

Review scripts/fresh-install-of-osx.sh following the checklist in the agent file.
```

### Option 3: Multi-Agent Review

For comprehensive review, use multiple agents in sequence:

```
1. First, review with shell-script-reviewer agent:
   [Provide agent file and script to review]

2. Then, review with security-reviewer agent:
   [Provide agent file and script to review]

3. Consolidate findings and prioritize fixes
```

## Workflow Recommendations

### For New Scripts

1. **Create script** following patterns in `.ai/domains/`
2. **Syntax check**: `zsh -n script.sh` (shell) or `ruby -c script.rb` (Ruby)
3. **Style review**: Use `shell-script-reviewer` or `ruby-script-reviewer`
4. **Security review**: Use `security-reviewer`
5. **Apply fixes** from review output
6. **Re-run syntax check**
7. **Manual test**
8. **Commit**

### For Script Edits

1. **Edit script** following patterns in `.ai/domains/`
2. **Syntax check**: `zsh -n script.sh` (shell) or `ruby -c script.rb` (Ruby)
3. **Style review**: Use appropriate reviewer agent (focused on changed sections)
4. **Security review**: If touching system calls, file operations, or credentials
5. **Apply fixes**
6. **Re-run syntax check**
7. **Manual test**
8. **Commit**

### For Startup Script Optimization

1. **Baseline**: Time startup (`ZSH_PROFILE=true zsh -i -c exit && zprof`)
2. **Performance review**: Use `shell-script-reviewer` with focus on performance section
3. **Apply optimizations** (cache expensive operations, eliminate subshells)
4. **Re-time startup** and verify improvement
5. **Regression test** (ensure functionality unchanged)
6. **Commit**

### For Security Audit

1. **Identify scripts** with privileged operations (sudo, rm, file operations)
2. **Security review**: Use `security-reviewer` on each
3. **Prioritize fixes** by risk level (CRITICAL → HIGH → MEDIUM → LOW)
4. **Apply fixes** starting with CRITICAL
5. **Re-review** after fixes
6. **Manual security test** if possible
7. **Commit**

## Agent Limitations

**All agents cannot**:
- Edit files directly (you must apply suggested changes)
- Run scripts to test behavior
- Check if referenced files exist on disk
- Verify git history or commit messages
- Test on actual vanilla OS or pre-configured machine
- Access network resources

**All agents can**:
- Analyze code syntax and structure
- Check against documented patterns in `.ai/domains/`
- Identify potential issues by static analysis
- Suggest improvements aligned with repository standards
- Provide line numbers and specific remediation steps

## Agent Dependencies

All agents require these files to be available and not truncated:

1. `.ai/instructions.md` - Main entry point, decision-making philosophy
2. `.ai/domains/shell-scripting.md` - Shell-specific patterns
3. `.ai/domains/ruby-scripting.md` - Ruby-specific patterns
4. `.ai/domains/logging-conventions.md` - Logging and color standards
5. `.ai/domains/path-constants.md` - Path variable conventions

If any of these files are truncated during agent execution, the agent will STOP and request full file content.

## Verifying Agent Suggestions

**CRITICAL**: Always verify agent suggestions against repository rules before applying.

Agents are tools, not authorities. They:
- May not understand historical optimization decisions (see `.ai/context.md`)
- May suggest patterns that conflict with repository conventions
- May not understand bootstrap constraints (fresh-install sequence)
- May be overly conservative or aggressive depending on tuning

**Verification checklist**:
- [ ] Does suggestion follow decision-making priority? (startup speed → maintainability → POSIX → zsh/Ruby idioms)
- [ ] Is suggestion compatible with Ruby 2.6? (if Ruby script)
- [ ] Does suggestion maintain bash compatibility? (if `.shellrc` or `.aliases`)
- [ ] Would suggestion work on vanilla OS? (if fresh-install script)
- [ ] Is suggestion documented in `.ai/domains/`? (if new pattern)
- [ ] Does suggestion preserve existing optimizations? (check `.ai/context.md`)

**When in doubt**: Reference the specific section in `.ai/domains/*.md` that applies to the suggestion.

## Example Agent Session

### Shell Script Review Example

**Input**:
```
Act as shell-script-reviewer (see .github/agents/shell-script-reviewer.agent.md).

Review: scripts/fresh-install-of-osx.sh

Focus areas:
- Idempotency (must work on vanilla OS and pre-configured machines)
- Error handling
- Bootstrap sequence compliance
```

**Expected Output**:
```markdown
## Shell Script Review: scripts/fresh-install-of-osx.sh

### Summary
Script is well-structured with good idempotency guards. Found 2 critical issues (unquoted variable, unsafe rm), 3 style issues, and 1 performance concern. Bootstrap sequence is correct. Overall quality: Good with fixes needed.

### Critical Issues (Fix Before Merge)
[Detailed findings with line numbers and fixes]

### Style Issues (Should Fix)
[Detailed findings with references to .ai/domains/shell-scripting.md]

[... rest of structured review ...]
```

### Security Review Example

**Input**:
```
Act as security-reviewer (see .github/agents/security-reviewer.agent.md).

Review: scripts/osx-defaults.sh

This script runs with user privileges, writes system preferences, and restarts system services.
```

**Expected Output**:
```markdown
## Security Review: scripts/osx-defaults.sh

### Summary
Found 1 HIGH risk issue (killall without validation), 2 MEDIUM risk issues (predictable temp file, overly permissive file creation). No CRITICAL findings. Overall risk: HIGH.

### HIGH Risk Findings (Fix Before Deploy)
[Detailed findings with exploit scenarios and remediations]

[... rest of structured review ...]
```

## Contributing New Agents

If you create a new agent for this repository:

1. **Follow the pattern** in existing agent files (YAML frontmatter, structured sections)
2. **Define clear scope** (what the agent reviews, what it doesn't)
3. **List prerequisites** (which `.ai/` files it needs to read)
4. **Provide output format** (markdown template for review reports)
5. **Include examples** (show what good review output looks like)
6. **Document limitations** (what the agent cannot do)
7. **Update this index** (add new agent to "Available Agents" section)

**Naming convention**: `<purpose>-<noun>.agent.md` (e.g., `shell-script-reviewer.agent.md`, `security-reviewer.agent.md`)

## Questions?

For detailed coding standards these agents check against:
- `.ai/instructions.md` - Main entry point and philosophy
- `.ai/domains/shell-scripting.md` - Complete shell scripting rules
- `.ai/domains/ruby-scripting.md` - Complete Ruby scripting rules
- `.ai/domains/logging-conventions.md` - Logging standards
- `.ai/context.md` - Historical optimization decisions

For agent usage questions or to suggest new agents, open an issue describing the review need.
