# Dead Corps - Development Workflow Guide

**Purpose:** Best practices for working with Claude across multiple conversations  
**Last Updated:** March 2, 2026

---

## 🔄 **Starting a New Chat**

### **Step 1: Load Context**

**First message in new chat:**
```
I'm working on Dead Corps game development.

Context document attached: [attach PROJECT_CONTEXT.md]
Current version: v0.19.4

[Your specific question or task]
```

**Alternative if no attachment:**
```
I'm working on Dead Corps.
Fetch context from Google Drive: DeadCorps_Context_v0.19.4.md
[Your task]
```

---

### **Step 2: Verify Context Loaded**

**Claude should respond with:**
- Acknowledgment of current version
- Summary of what's implemented
- Specific answer to your question

**If Claude seems confused:**
- Paste relevant section from context doc
- Reference specific version numbers
- Provide code snippets if needed

---

## 📋 **Development Practices**

### **Rule 1: Ask Before Building**

**DON'T:**
```
❌ "Add a new zombie type with special abilities"
```

**DO:**
```
✅ "I want to add a new zombie type with dash ability. 
   How should this integrate with existing systems?
   What's your recommended approach?"
```

**Why:** Prevents wasted effort on wrong approaches, ensures consistency with existing code.

---

### **Rule 2: Describe Approach First**

**When Claude suggests implementation:**
1. Claude explains approach
2. You review and approve/modify
3. Then Claude implements

**Example Flow:**
```
You: "Add waypoint pauses to patrol system"

Claude: "I'd add an @export array for pause durations,
         check at waypoint arrival, use timer before advancing.
         Should I proceed?"

You: "Yes, but make pause optional per waypoint"

Claude: [implements with that modification]
```

---

### **Rule 3: One Feature at a Time**

**DON'T:**
```
❌ "Add pauses, swing arcs, and facing overrides to waypoints"
```

**DO:**
```
✅ "Add waypoint pause durations first"
   [test and verify]
✅ "Now add swing arcs at waypoints"
   [test and verify]
✅ "Finally add facing overrides"
```

**Why:** Easier to debug, clearer git history, incremental testing.

---

### **Rule 4: Verify Before Moving On**

**After each change:**
1. **Test** the feature
2. **Report** results (working/broken/partial)
3. **Debug** if needed
4. **Then** move to next feature

**Don't skip testing!** Bugs compound.

---

## 📦 **Output Management**

### **Always Use Zip Files**

**Claude should:**
- Package changes in zip files
- Include version number in filename
- Example: `dead-corps-v0.20.0-WAYPOINT-PAUSES.zip`

**You should:**
- Extract to project directory
- Test changes
- Commit to git if working

---

### **File Organization**

**Zips should include:**
```
baseline-v0.12.0-no-editor/
├─ scripts/
│  ├─ zombie.gd
│  ├─ human.gd
│  └─ unit.gd
├─ scenes/
│  ├─ zombie.tscn
│  └─ human.tscn
└─ docs/
   ├─ CHANGELOG_vX.X.X.md
   ├─ PROJECT_CONTEXT.md (updated)
   └─ [feature-specific docs]
```

**Never include:**
- `.import` files
- `.godot/` directory
- Binary assets (unless new)

---

## 🔢 **Versioning**

### **Version Number Format**

**Format:** `vMAJOR.MINOR.PATCH`

**Examples:**
- `v0.19.4` → Current version
- `v0.20.0` → Next feature (waypoint pauses)
- `v0.20.1` → Bug fix for v0.20.0
- `v1.0.0` → First complete release

---

### **When to Increment:**

**MAJOR (v1.0.0):**
- Complete game release
- Major gameplay changes
- Breaking changes to save files

**MINOR (v0.X.0):**
- New features
- New systems
- Phase completions (Phase C = v0.20.0)

**PATCH (v0.19.X):**
- Bug fixes
- Small tweaks
- No new features

---

### **Always Update:**

After each change:
1. **Increment version** in context doc
2. **Add changelog** entry
3. **Update "What's Working"** section
4. **Note any breaking changes**

---

## 📝 **Documentation Requirements**

### **Every Feature Should Have:**

**1. Changelog Entry:**
```markdown
## v0.20.0 - Waypoint Pauses

**Added:**
- Per-waypoint pause durations
- Pause timer system
- Visual indicator for paused sentries

**Changed:**
- update_patrol() now handles pause state

**Fixed:**
- [any bugs discovered during implementation]
```

**2. Usage Documentation:**
```markdown
## How to Use Waypoint Pauses

Setup:
1. Add waypoints to sentry
2. Set patrol_pause_durations array
3. Example: [2.0, 0.0, 3.0] = pause 2s at waypoint1, etc.
```

**3. Context Doc Update:**
```markdown
✅ Patrol System Phase C (v0.20.0):
- Per-waypoint pause durations
- [description of how it works]
```

---

## 🐛 **Debugging Protocol**

### **When Something Breaks:**

**1. Gather Information:**
```
- What version were you on? (v0.19.4)
- What did you just add? (waypoint pauses)
- What's the error? (paste console output)
- What were you testing? (sentry patrol with 3 waypoints)
```

**2. Provide Context:**
```
"Working on v0.20.0 waypoint pauses.
 Console shows: [error message]
 Expected: sentry pauses at waypoint 2
 Actual: sentry skips waypoint entirely"
```

**3. Include Code If Relevant:**
```gdscript
// Paste the specific function that's broken
// Not the entire 1000-line script
```

---

### **Debug Output:**

**Add print statements:**
```gdscript
print("🔍 DEBUG: Reached waypoint ", index)
print("  Pause duration: ", pause_duration)
print("  Timer remaining: ", pause_timer)
```

**Use emojis for visibility:**
- 🔍 DEBUG
- ✅ SUCCESS
- ❌ ERROR
- ⚠️ WARNING

---

## 🔄 **Git Workflow (Recommended)**

### **Basic Setup:**

```bash
git init
git add .
git commit -m "v0.19.4 - Patrol Phase B2 complete"
```

---

### **After Each Feature:**

```bash
# Make changes via Claude
# Test changes

git add .
git commit -m "v0.20.0 - Add waypoint pause durations"
git tag v0.20.0
```

---

### **Benefits:**

- ✅ Easy rollback if something breaks
- ✅ Version history
- ✅ Can compare changes
- ✅ Backup of working states

**Not Required:** But highly recommended for sanity.

---

## 💾 **Context Document Maintenance**

### **Update After:**

- ✅ New features implemented
- ✅ Major bugs fixed
- ✅ System changes
- ✅ Version increments

### **Don't Update For:**

- ❌ Minor tweaks
- ❌ Documentation-only changes
- ❌ Experiments that didn't work

---

### **Updating Process:**

**In the chat where work was done:**
```
"Update PROJECT_CONTEXT.md with v0.20.0 changes"
```

**Claude will:**
1. Increment version number
2. Add new feature to "What's Working"
3. Update any changed systems
4. Note any new known issues

**You should:**
1. Save updated context doc to Drive
2. Keep filename current: `DeadCorps_Context_v0.20.0.md`

---

## 🎯 **Effective Claude Prompts**

### **Good Prompts:**

✅ **Specific:**
```
"Add a 2-second pause at waypoint 2.
 Use a timer that counts down.
 Resume patrol when timer reaches 0."
```

✅ **Context-Aware:**
```
"Building on the existing patrol system (Phase B2),
 add per-waypoint pause support."
```

✅ **With Constraints:**
```
"Add pauses but keep backwards compatible
 with waypoints that don't have pauses set."
```

---

### **Bad Prompts:**

❌ **Vague:**
```
"Make the game better"
"Fix the bugs"
```

❌ **No Context:**
```
"Add zombies" 
(zombies already exist - which new type?)
```

❌ **Too Broad:**
```
"Implement the entire Phase C system"
(break into smaller tasks)
```

---

## 🚨 **When Things Go Wrong**

### **Claude Makes Breaking Changes:**

**STOP and:**
1. Don't extract the zip yet
2. Ask Claude to explain what changed
3. Review changes before applying
4. Can request modifications

**Example:**
```
"Wait - this changes how existing patrols work.
 Can you make it backwards compatible instead?"
```

---

### **Lost Context Mid-Conversation:**

**Happens when:**
- Conversation gets very long
- Claude seems to forget earlier decisions
- Suggestions conflict with what you built

**Solution:**
```
"Reminder: We're using visual waypoints (Phase B2).
 Waypoints are child Node2D nodes, not typed arrays.
 Current version: v0.20.0"
```

---

### **Can't Reproduce Your Setup:**

**Claude needs:**
- Exact version number
- Specific error messages
- Code snippets of relevant functions
- Description of test scenario

**Template:**
```
Version: v0.20.0
Feature: Waypoint pauses
Error: [paste console output]
Test: Sentry with 3 waypoints, pause at waypoint 2
Expected: Pause for 2 seconds
Actual: Sentry walks straight through

Relevant code:
[paste update_patrol function]
```

---

## 📊 **Progress Tracking**

### **Keep a TODO List:**

**In Google Drive or local file:**
```markdown
# Dead Corps TODO

## In Progress (v0.20.0)
- [ ] Waypoint pause durations

## Next Up (v0.21.0)
- [ ] Waypoint swing arcs
- [ ] Waypoint facing overrides

## Backlog
- [ ] New zombie types
- [ ] Level editor
- [ ] Save/load system

## Completed
- [x] Phase A: Sentry system (v0.14.0)
- [x] Phase B1: Manual patrol (v0.18.0)
- [x] Phase B2: Visual waypoints (v0.19.0)
```

---

### **Reference in Chats:**

```
"Working on waypoint pauses from TODO list.
 This is v0.20.0, part of Phase C."
```

**Helps Claude understand priorities and context.**

---

## 🎓 **Learning from Iterations**

### **Document Patterns:**

**When you find good solutions:**
```markdown
## Pattern: Optional Array Features

Problem: Want feature per-waypoint but not all waypoints need it
Solution: Use array same size as waypoints, use default value for "no feature"
Example: pause_durations = [2.0, 0.0, 3.0] where 0.0 = no pause

Works for: pauses, swing toggles, facing overrides
```

---

### **Note Design Decisions:**

**Add to context doc:**
```markdown
## Why Swing Disabled While Patrolling

Tried: Swing while walking
Problem: Jerky, unnatural movement
Solution: Only swing when stationary
Future: Pause at waypoints to swing/look around
```

**Prevents revisiting failed approaches.**

---

## ⚡ **Rapid Development Tips**

### **Batch Questions:**

**Instead of:**
```
"How do I add pauses?"
[wait for response]
"How do I test it?"
[wait for response]
"What about backwards compatibility?"
```

**Do:**
```
"I want to add waypoint pauses.
 Questions:
 1. How should I structure the pause duration array?
 2. Best way to test this?
 3. How to keep backwards compatible?
 
 Let's discuss approach before implementing."
```

**Saves round trips!**

---

### **Use Reference Docs:**

**For common questions:**
- Check PATROL_QUICKSTART_PHASE_B1.md first
- Check NAVIGATION_TROUBLESHOOTING.md for nav issues
- Check PROJECT_CONTEXT.md for current state

**Only ask Claude if docs don't answer.**

---

## 🎯 **Summary: Golden Rules**

1. **Load context** at start of every new chat
2. **Ask before building** - discuss approach first
3. **One feature at a time** - test between changes
4. **Version everything** - increment, document, commit
5. **Update context doc** - keep it current
6. **Git commit** working states - easy rollback
7. **Specific prompts** - give context and constraints
8. **Batch questions** - save round trips
9. **Document patterns** - avoid repeating mistakes
10. **Test thoroughly** - bugs compound

---

## 📞 **Quick Reference**

**Starting Fresh Chat:**
```
"Working on Dead Corps v0.19.4
 Context: [attach PROJECT_CONTEXT.md]
 Task: [specific feature/bug]"
```

**Reporting Bug:**
```
"Bug in v0.20.0
 Feature: [what you were testing]
 Error: [paste console]
 Expected vs Actual: [describe]"
```

**Requesting Feature:**
```
"Add [feature] to v0.20.0
 It should: [requirements]
 Constraints: [backwards compat, etc]
 Discuss approach before implementing"
```

**Updating Docs:**
```
"Update PROJECT_CONTEXT.md:
 - Version → v0.20.0
 - Add waypoint pauses to 'What's Working'
 - Note: [any design decisions]"
```

---

**END OF WORKFLOW GUIDE**

*Follow these practices to maintain productivity across conversations.*
*Update this doc if you find better workflows!*
*Store alongside PROJECT_CONTEXT.md in Google Drive.*
