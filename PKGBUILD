# Contributor: Andrey Vihrov <andrey.vihrov at gmail.com>
# Contributor: Frank Vanderham <twelve.eighty (at) gmail.>
# Contributor: USA-RedDragon (AUR)

pkgname=broadcom-wl-dkms
pkgver=6.30.223.271
pkgrel=12
pkgdesc="Broadcom 802.11 Linux STA wireless driver"
arch=('i686' 'x86_64')
url="https://www.broadcom.com/support/download-search/?pf=Wireless+LAN+Infrastructure"
license=('custom')
depends=('dkms')
conflicts=('broadcom-wl')
install=broadcom-wl-dkms.install
source=('broadcom-wl-dkms.conf'
        'dkms.conf.in'
        '001-null-pointer-fix.patch'
        '002-rdtscl.patch'
        '003-linux47.patch'
        '004-linux48.patch'
        '005-debian-fix-kernel-warnings.patch'
        '099-kernel-7.0-compat.patch'
        '100-kernel-7.1-compat.patch')
source_i686=("https://docs.broadcom.com/docs-and-downloads/docs/linux_sta/hybrid-v35-nodebug-pcoem-${pkgver//./_}.tar.gz")
source_x86_64=("https://docs.broadcom.com/docs-and-downloads/docs/linux_sta/hybrid-v35_64-nodebug-pcoem-${pkgver//./_}.tar.gz")
sha256sums=('b97bc588420d1542f73279e71975ccb5d81d75e534e7b5717e01d6e6adf6a283'
            '7bcdd485343b4bba75c2f8b248e7cb4af57e4e585cb383c79bce8e815569c195'
            '32e505a651fdb9fd5e4870a9d6de21dd703dead768c2b3340a2ca46671a5852f'
            '4ea03f102248beb8963ad00bd3e36e67519a90fa39244db065e74038c98360dd'
            '30ce1d5e8bf78aee487d0f3ac76756e1060777f70ed1a9cf95215c3a52cfbe2e'
            '09d709df0c764118ca43117f5c096163d9669a28170da8476d4b8211bd225d2e'
            '2306a59f9e7413f35a0669346dcd05ef86fa37c23b566dceb0c6dbee67e4d299'
            '13dc2dce5773444bcd3d028c9a0007d4f2e945e99043c49c2d1ec490bf1749fa'
            'c61fc40128c898a075302e4d25f8be41cb5d88abce0b7fd4ba726c230d41d7f4')
sha256sums_i686=('4f8b70b293ac8cc5c70e571ad5d1878d0f29d133a46fe7869868d9c19b5058cd')
sha256sums_x86_64=('5f79774d5beec8f7636b59c0fb07a03108eef1e3fd3245638b20858c714144be')

prepare() {
  sed -i -e '/BRCM_WLAN_IFNAME/s/eth/wlan/' src/wl/sys/wl_linux.c
  sed -i -e "/EXTRA_LDFLAGS/s|\$(src)/lib|/usr/lib/${pkgname}|" Makefile
  sed -i -e 's/EXTRA_LDFLAGS/ldflags-y/g' Makefile
  sed -i -e 's/EXTRA_CFLAGS/ccflags-y/g' Makefile

  sed -e "s/@PACKAGE_VERSION@/${pkgver}/" dkms.conf.in > dkms.conf

  # net/lib80211.h was removed from the kernel; the driver only uses it
  # for the lib80211_crypto_ops struct tag (never calls into the real
  # module), so vendor the last public header instead of linking lib80211.
  mkdir -p src/include/net
  cat > src/include/net/lib80211.h <<'LIB80211_EOF'
/* SPDX-License-Identifier: GPL-2.0 */
/*
 * lib80211.h -- common bits for IEEE802.11 wireless drivers
 *
 * Copyright (c) 2008, John W. Linville <linville@tuxdriver.com>
 *
 * Vendored locally: removed from upstream kernel headers, last public
 * version pulled from torvalds/linux v6.12 include/net/lib80211.h
 */

#ifndef LIB80211_H
#define LIB80211_H

#include <linux/types.h>
#include <linux/list.h>
#include <linux/atomic.h>
#include <linux/if.h>
#include <linux/skbuff.h>
#include <linux/ieee80211.h>
#include <linux/timer.h>
#include <linux/seq_file.h>

#define NUM_WEP_KEYS	4

enum {
	IEEE80211_CRYPTO_TKIP_COUNTERMEASURES = (1 << 0),
};

struct module;

struct lib80211_crypto_ops {
	const char *name;
	struct list_head list;

	void *(*init) (int keyidx);
	void (*deinit) (void *priv);

	int (*encrypt_mpdu) (struct sk_buff * skb, int hdr_len, void *priv);
	int (*decrypt_mpdu) (struct sk_buff * skb, int hdr_len, void *priv);

	int (*encrypt_msdu) (struct sk_buff * skb, int hdr_len, void *priv);
	int (*decrypt_msdu) (struct sk_buff * skb, int keyidx, int hdr_len,
			     void *priv);

	int (*set_key) (void *key, int len, u8 * seq, void *priv);
	int (*get_key) (void *key, int len, u8 * seq, void *priv);

	void (*print_stats) (struct seq_file *m, void *priv);

	unsigned long (*get_flags) (void *priv);
	unsigned long (*set_flags) (unsigned long flags, void *priv);

	int extra_mpdu_prefix_len, extra_mpdu_postfix_len;
	int extra_msdu_prefix_len, extra_msdu_postfix_len;

	struct module *owner;
};

struct lib80211_crypt_data {
	struct list_head list;
	const struct lib80211_crypto_ops *ops;
	void *priv;
	atomic_t refcnt;
};

struct lib80211_crypt_info {
	char *name;
	spinlock_t *lock;

	struct lib80211_crypt_data *crypt[NUM_WEP_KEYS];
	int tx_keyidx;
	struct list_head crypt_deinit_list;
	struct timer_list crypt_deinit_timer;
	int crypt_quiesced;
};

int lib80211_crypt_info_init(struct lib80211_crypt_info *info, char *name,
                                spinlock_t *lock);
void lib80211_crypt_info_free(struct lib80211_crypt_info *info);
int lib80211_register_crypto_ops(const struct lib80211_crypto_ops *ops);
int lib80211_unregister_crypto_ops(const struct lib80211_crypto_ops *ops);
const struct lib80211_crypto_ops *lib80211_get_crypto_ops(const char *name);
void lib80211_crypt_delayed_deinit(struct lib80211_crypt_info *info,
				    struct lib80211_crypt_data **crypt);

#endif /* LIB80211_H */
LIB80211_EOF
}

package() {
  local dest="${pkgdir}/usr/src/${pkgname/-dkms/}-${pkgver}"
  mkdir -p "${dest}"
  cp -a src Makefile dkms.conf "${dest}"
  install -D -m 0644 -t "${dest}/patches" *.patch

  install -D -m 0644 lib/wlc_hybrid.o_shipped "${pkgdir}/usr/lib/${pkgname}/wlc_hybrid.o_shipped"

  install -D -m 0644 broadcom-wl-dkms.conf "${pkgdir}/usr/lib/modprobe.d/broadcom-wl-dkms.conf"

  local ldir="${pkgdir}/usr/share/licenses/${pkgname}"
  install -D -m 0644 lib/LICENSE.txt "${ldir}/LICENSE.shipped"
  sed -n -e '/Copyright/,/SOFTWARE\./{s/^ \* //;p}' src/wl/sys/wl_linux.c > "${ldir}/LICENSE.module"
}

# vim:set ts=2 sw=2 et:
