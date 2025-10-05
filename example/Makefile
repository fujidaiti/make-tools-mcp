.PHONY: analyze format fix tidyup test

analyze:
	 fvm dart analyze .

# Normal comments

# format runs the "format" command with the "--set-exit-if-changed" flag
format:
	 fvm dart format .

# fix runs the "fix" command with the "--apply" flag
fix:
	fvm dart fix --apply

# tidyup is a shortcut for fix, format, and analyze
#
# This runs "fix", "format", and "analyze" in sequence.
# The second line of the description.
#
#! plain comment, should be ignored
# The third line of the description.
tidyup: fix format analyze

test:
	fvm flutter test -r failures-only
