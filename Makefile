WEBDIR = /web/customers/hashcache.rkeene.org

all:
	@echo "Nothing to do."

install:
	cp hashcache.cgi "$(WEBDIR)/index.cgi"
	cp htaccess "$(WEBDIR)/.htaccess"
