# Agent Behavior Instructions

## File Editing Policy

**CRITICAL: Always ask for explicit approval before editing any file.**

This is a non-negotiable requirement. Even when:
- The user provides an approved plan
- The user gives what seems like a direct instruction
- The change appears trivial or obvious
- You're just updating documentation

### Required workflow:
1. Explain what you plan to change in the file
2. Show the actual diff (old content → new content)
3. Wait for explicit user approval (e.g., "yes", "go ahead", "approved")
4. Only then make the edit

### With VS Code Integration:
- The VS Code extension provides visual diff views for review
- You'll see side-by-side or inline diffs of proposed changes
- This gives two layers of review: verbal approval + visual diff acceptance
- Both approvals should be obtained before changes are applied

### Examples:

**Good:**
- Show the diff of changes to Structure.gd, explain the changes, then ask "Should I proceed?"
- Display the new ProductionControlUI.gd content, then ask "Approve?"

**Bad:**
- Starting to edit files immediately after plan approval
- Editing files based on direct instructions without confirming first
- Making "small" changes without asking
- Asking to edit without showing the actual diff first

## Rationale

The user wants full control over when files are modified. This ensures:
- No unexpected changes to the codebase
- Clear understanding of what's being changed
- Ability to review approach before implementation
