Display the WoW System status including current score, configuration, active handlers, and session information.

Run this command to show the full status:

```bash
source ~/.claude/wow-system/src/core/orchestrator.sh && \
source ~/.claude/wow-system/src/ui/display.sh && \
wow_init && \
display_session_banner
```

This will show:
- Current WoW System version
- Your behavioral score (0-100)
- Active enforcement settings
- Number of handlers loaded
- Session start time and location
- Performance trends (if available)
- Detected patterns (if any)
