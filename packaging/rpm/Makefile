PACKAGE_NAME?=	redborder-common

VERSION?=	$(shell git describe --abbrev=6 --tags HEAD --always | sed 's/-/_/g')

BUILD_NUMBER?= 1
GOVC_VERSION?= 0.54.1

MOCK_CONFIG?=default

RESULT_DIR?=pkgs

all: rpm


SOURCES:
	mkdir -p SOURCES

archive: SOURCES
  cd ../../ && \
    git archive --prefix=$(PACKAGE_NAME)-$(VERSION)/ \
            -o packaging/rpm/SOURCES/$(PACKAGE_NAME)-$(VERSION).tar.gz $(LATEST)
			--transform="s/./$(PACKAGE_NAME)-$(VERSION)/" ./

build_prepare: archive
	mkdir -p $(RESULT_DIR)
	rm -f $(RESULT_DIR)/$(PACKAGE_NAME)*.rpm


srpm: build_prepare
	/usr/bin/mock \
		-r $(MOCK_CONFIG) \
		--define "__version $(VERSION)" \
		--define "__release $(BUILD_NUMBER)" \
		--resultdir=$(RESULT_DIR) \
		--buildsrpm \
		--spec=${PACKAGE_NAME}.spec \
		--sources=SOURCES
	@echo "======= Source RPM now available in $(RESULT_DIR) ======="

rpm: srpm govc-rpm
	/usr/bin/mock \
		-r $(MOCK_CONFIG) \
		--define "__version $(VERSION)"\
		--define "__release $(BUILD_NUMBER)"\
		--resultdir=$(RESULT_DIR) \
		--rebuild $(RESULT_DIR)/$(PACKAGE_NAME)*.src.rpm
	@echo "======= Binary RPMs now available in $(RESULT_DIR) ======="

govc-rpm: SOURCES
	wget -c -O SOURCES/govc-$(GOVC_VERSION)_Linux_x86_64.tar.gz https://github.com/vmware/govmomi/releases/download/v$(GOVC_VERSION)/govc_Linux_x86_64.tar.gz
	/usr/bin/mock \
		-r $(MOCK_CONFIG) \
		--define "__version $(GOVC_VERSION)" \
		--define "__release $(BUILD_NUMBER)" \
		--resultdir=$(RESULT_DIR) \
		--buildsrpm \
		--spec=govc.spec \
		--sources=SOURCES
	/usr/bin/mock \
		-r $(MOCK_CONFIG) \
		--define "__version $(GOVC_VERSION)" \
		--define "__release $(BUILD_NUMBER)" \
		--resultdir=$(RESULT_DIR) \
		--rebuild $(RESULT_DIR)/govc-$(GOVC_VERSION)*.src.rpm
	@echo "======= Binary govc RPM now available in $(RESULT_DIR) ======="

clean:
	rm -rf SOURCES pkgs

distclean: clean
	rm -f build.log root.log state.log available_pkgs installed_pkgs \
		*.rpm *.tar.gz

