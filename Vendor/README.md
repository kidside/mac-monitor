m1ddc is vendored from https://github.com/waydabber/m1ddc at commit
04d949794102eb8df01ad3681afff6464a3eede2, under its included MIT license.
It is compiled as a separate, short-lived helper, with MAX_DISPLAYS=32.
Mac Monitor only invokes its luminance read/write commands, targeting a specific display ID.

Local changes validate the DDC reply header, feature code, result and checksum,
decode 16-bit values without oversized memory reads, retry invalid replies, and
add `get-json luminance` to return current/maximum from the same response.
Get VCP requests now include the host source address in their checksum, which
is required by the Mi Monitor on the M4 Pro built-in HDMI/AppleDCPPS190 path.
Reads use subaddress 0, an 11-byte reply and a 50 ms settle time. Request frame
length is derived from the length byte so a zero checksum is still sent.

Security fixes in beta.2 reject display indices below 1, overflow and missing
identifiers. Numeric writes require complete 16-bit values; relative changes
clamp before adding, avoiding signed overflow. Incomplete CLI commands are
rejected before accessing hardware. Selection and numeric boundary tests run
with address/undefined-behavior sanitizers where applicable.
