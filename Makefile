WEBDIR = /web/customers/hashcache.rkeene.org

all: hashcache

hashcache: hashcache.cr
	crystal build --release -o hashcache hashcache.cr
	strip hashcache

install:
	cp hashcache "$(WEBDIR)/index.cgi"
	cp htaccess "$(WEBDIR)/.htaccess"

clean:
	rm -f hashcache hashcache.o

distclean: clean

.PHONY: all install clean distclean
