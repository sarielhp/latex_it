# You can't use `\spacefactor' in vertical mode

## Description
`\spacefactor` modifies inter-word spacing and can only be set in horizontal paragraph mode.

## Remediation
Ensure `\spacefactor` is set within text/paragraph mode, not after `\par` or in vertical mode.
