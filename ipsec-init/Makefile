include $(TOPDIR)/rules.mk

PKG_NAME:=ipsec-init
PKG_RELEASE:=14
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)/template
  SUBMENU:=VPN
  SECTION:=net
  CATEGORY:=Network
  TITLE:=StrongSwan init
  PKGARCH:=all
endef

define Package/$(PKG_NAME)/description
  StrongSwan Meta and init scripte
endef

define Package/$(PKG_NAME)
  $(call Package/ipsec-init/template)
  MENU:=1
  EXTRA_DEPENDS:=iptables-mod-ipsec, kmod-xfrm-interface, \
  kmod-crypto-sha256, kmod-crypto-sha512, \
  xfrm, luci-proto-xfrm, ca-certificates, \
  strongswan-charon, strongswan-pki, \
  strongswan-swanctl, \
  strongswan-mod-eap-identity, \
  strongswan-mod-eap-mschapv2, strongswan-mod-kernel-netlink, \
  strongswan-mod-openssl, strongswan-mod-pem, \
  strongswan-mod-socket-default, \
  strongswan-mod-x509, \
  strongswan-mod-updown
endef

define Package/$(PKG_NAME)/conffiles
/etc/config/ipsec
/etc/ipsec_updown.sh
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef
define Build/Configure
endef
define Build/Compile
endef

define Package/$(PKG_NAME)/install
	# $(INSTALL_DIR) $(1)/etc/config
	# $(INSTALL_DATA) files/ipsec.config $(1)/etc/config/ipsec
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) files/ipsec.init.sh $(1)/etc/init.d/ipsec
	$(INSTALL_BIN) files/ipsec_updown.sh $(1)/etc/ipsec_updown.sh
endef

$(eval $(call BuildPackage,ipsec-init))
