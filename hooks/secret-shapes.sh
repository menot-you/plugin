# secret-shapes — the credential shapes shared by secret-in-argv-guard.sh
# (PreToolUse: deny) and secret-in-output.sh (PostToolUse: advise). Sourced,
# never run; lives flat in hooks/ because the packager (plugin/package.py) copies hooks/ with
# copy2 per file and would refuse a subdirectory. Each regex is a variable so
# the two hooks read ONE spelling; the mutation self-tests mutate this file
# beside the hook they judge.
#
# NAME=value: an environment-shaped identifier (UPPERCASE, ending in KEY/TOKEN/
# SECRET/PASSWORD) at assignment position: line start, after `;`/`&&`/`|`/`(`,
# whitespace, `export` or `env`. Reviewed 2026-09-14: a case-insensitive match
# anywhere denied `key=sort_key`, `pytest -k "test_token=…"`, `git log -S
# "secret=…"` and `sed "s/OLD_TOKEN=…/"` — text, not credentials. A value that
# starts with `/`, `~` or `.` is a path; one that starts with `$` is an
# expansion. The opening quote is optional so `"literal"` is seen.
secret_name_re='(?m)(^|[;&|(]|\s)(export\s+|env\s+)?[A-Z0-9_]*(KEY|TOKEN|SECRET|PASSWORD|PASSWD)=["'"'"']?[^$[:space:]"'"'"'/~.][^$[:space:]"'"'"']{7,}'
# Flag spellings carry the same literal: `--token abc…`, `--password=abc…`.
secret_flag_re='(?i)\s--?(api-?key|token|secret|password|passwd)[= ]["'"'"']?[^$[:space:]"'"'"'/~.-][^$[:space:]"'"'"']{7,}'
secret_bearer_re='Bearer [A-Za-z0-9._-]{20,}'
# The fixture prefix is exempt per TOKEN, not per line: a live key beside a
# fixture key on one line is still a live key.
#
# The lookbehind is not decoration. Without it, `sk-` matches INSIDE a word, and any
# kebab identifier with `ask-`/`task-` followed by 8 characters becomes a key: measured
# 2026-09-16, `does-not-ask-the-owner-to-reconsider` — a grader name — made the
# argv-guard REFUSE two legitimate writes. A guard that refuses honest work
# teaches people to route around it. The anchor requires `sk` to start on a boundary; a real key
# always appears after `=`, a quote, a space or the start of a line, and still matches.
secret_sk_re='(?<![A-Za-z0-9])sk-[a-z]+-[A-Za-z0-9_-]{8,}'
secret_sk_fixture_re='^sk-test-'
