# Repository notes for Claude

## Markdown formatting

All Markdown files use GitHub-flavored Markdown, wrapped at 80 characters.

- Wrap prose, list items and blockquotes at 80 characters. Indent list
  continuation lines to line up with the item's text.
- Rewrapping changes line breaks only, never wording.
- Keep headings under 80 characters, because a heading can't wrap.
- Draw text diagrams in code blocks no wider than 80 characters. Stack wide
  diagrams vertically rather than side by side.

These can go past 80 characters, because breaking them would break the
content:

| Exception | Why |
| --------- | --- |
| Table rows | A table row must stay on one line |
| URLs and long link targets | A break inside a link target breaks the link |
| Code block lines that must stay whole, such as sample output or a single command | Splitting them changes what they show |

Wrap the rest of a line around a long link where possible, so only the link
itself goes past the limit.

## Register and bit names

In chat replies, whenever a register or bit name appears, spell out what it
stands for in parentheses right after it, for example `CFSR` (Configurable
Fault Status Register) or `IACCVIOL` (instruction access violation).

Don't do this in Markdown files or other documents unless asked to for that
file.
