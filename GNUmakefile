.PHONY: $(MAKECMDGOALS) __default

.NOTPARALLEL:

__default $(firstword $(MAKECMDGOALS)):
	@scripts/make-with-log $(MAKECMDGOALS)

$(wordlist 2, $(words $(MAKECMDGOALS)), $(MAKECMDGOALS)):
	@# ignore
