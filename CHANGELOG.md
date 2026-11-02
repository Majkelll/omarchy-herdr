# Changelog

## 1.0.0 - 2026-11-01

- First release: every herdr server on this machine and on the machines you
  add over SSH, in the Omarchy bar, with the agents inside them.
- A badge on the icon counts the agents blocked on an answer, or else the ones
  that finished, or else the ones still working; an idle herd shows none.
- Every state is drawn in herdr's own colour for it, read from herdr's theme,
  its overrides and `auto_switch`, and from the terminal palette for herdr's
  `terminal` theme. Idle agents are a hollow ring, as in herdr's sidebar.
- One click lands you in a session: the window already showing it is raised
  on its workspace, or a terminal is opened on it, locally or over SSH.
  Clicking an agent focuses its pane first.
- Machines are added from a form with a Test button that checks ssh, herdr
  and its version before saving. For a machine without herdr it copies
  herdr's install command to the clipboard; nothing is downloaded or run.
- Read-only towards herdr: a refresh never stops a server or deletes a
  session. Background SSH never prompts, every read is capped in bytes and
  every call has a timeout.
- With a bar on more than one monitor, only one copy of the widget polls.
