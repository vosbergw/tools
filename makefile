
# make install -> install tools in ~/bin

$(HOME)/bin/$(basename $(wildcard *.sh)): $(wildcard *.sh)
	install -T $(notdir $@).sh $(basename $@)

