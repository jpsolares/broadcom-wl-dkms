#!/usr/bin/env bash
set -euo pipefail

PKGVER="6.30.223.271"
MODNAME="broadcom-wl"
KVER="$(uname -r)"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Ejecuta esto con sudo:"
  echo "  sudo $0"
  exit 1
fi

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
pkgver_us="${PKGVER//./_}"
tarball_name="hybrid-v35_64-nodebug-pcoem-${pkgver_us}.tar.gz"
tarball="${BRCM_TARBALL:-${here}/${tarball_name}}"
tarball_url_primary="${BRCM_TARBALL_URL:-https://docs.broadcom.com/docs-and-downloads/docs/atheros/${tarball_name}}"
tarball_url_fallback="https://docs.broadcom.com/docs-and-downloads/docs/linux_sta/${tarball_name}"

if [[ ! -f "${tarball}" ]]; then
  echo "No encuentro el tarball: ${tarball}"
  echo
  echo "Nota: por licencia/tamaño no se incluye el tarball en este repo."
  echo "URL esperada:"
  echo "  ${tarball_url_primary}"
  [[ -n "${BRCM_TARBALL_URL:-}" ]] || echo "  ${tarball_url_fallback}"
  echo
  echo "Intentando descargarlo..."
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --retry-delay 2 -o "${tarball}" "${tarball_url_primary}" || {
      if [[ -z "${BRCM_TARBALL_URL:-}" ]]; then
        echo "WARN: descarga falló, intentando URL alterna..."
        curl -fL --retry 3 --retry-delay 2 -o "${tarball}" "${tarball_url_fallback}"
      else
        exit 1
      fi
    }
  elif command -v wget >/dev/null 2>&1; then
    wget -O "${tarball}" "${tarball_url_primary}" || {
      if [[ -z "${BRCM_TARBALL_URL:-}" ]]; then
        echo "WARN: descarga falló, intentando URL alterna..."
        wget -O "${tarball}" "${tarball_url_fallback}"
      else
        exit 1
      fi
    }
  else
    echo "ERROR: no tengo curl/wget para descargar. Instala uno de los dos y reintenta."
    exit 1
  fi
fi

dest="/usr/src/${MODNAME}-${PKGVER}"

echo "Kernel: ${KVER}"
echo "Destino DKMS: ${dest}"

echo
echo "1) Preparando dependencias (si falta algo, instálalo con apt):"
echo "   sudo apt update"
echo "   sudo apt install -y dkms build-essential linux-headers-${KVER} clang lld patch"
echo

if command -v apt-get >/dev/null 2>&1; then
  apt-get update -y || true
  apt-get install -y dkms build-essential "linux-headers-${KVER}" clang lld patch || true
fi

echo
echo "2) Limpiando intentos anteriores (si existen)"
dkms remove broadcom-sta/"${PKGVER}" --all --force >/dev/null 2>&1 || true
dkms remove "${MODNAME}"/"${PKGVER}" --all --force >/dev/null 2>&1 || true

if [[ -e "${dest}" ]]; then
  echo
  echo "ERROR: ya existe ${dest}."
  echo "Bórralo o renómbralo y vuelve a correr el script:"
  echo "  sudo rm -rf ${dest}"
  exit 1
fi

mkdir -p "${dest}"
tar -xzf "${tarball}" -C "${dest}"

echo
echo "3) Ajustes necesarios para kernel moderno"

# interface name default
sed -i -e '/BRCM_WLAN_IFNAME/s/eth/wlan/' "${dest}/src/wl/sys/wl_linux.c"

# kbuild stopped honoring EXTRA_CFLAGS/EXTRA_LDFLAGS
sed -i -e 's/EXTRA_LDFLAGS/ldflags-y/g' -e 's/EXTRA_CFLAGS/ccflags-y/g' "${dest}/Makefile"

# net/lib80211.h removed upstream; vendor last public header
mkdir -p "${dest}/src/include/net"
cat > "${dest}/src/include/net/lib80211.h" <<'LIB80211_EOF'
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

echo
echo "4) Copiando parches y dkms.conf"
mkdir -p "${dest}/patches"
cp -a "${here}/"0*.patch "${here}/"100-*.patch "${dest}/" || true
cp -a "${here}/"0*.patch "${here}/"100-*.patch "${dest}/patches/" || true

cat > "${dest}/dkms.conf" <<EOF
PACKAGE_NAME="${MODNAME}"
PACKAGE_VERSION="${PKGVER}"
BUILT_MODULE_NAME[0]="wl"
DEST_MODULE_LOCATION[0]="/kernel/drivers/net/wireless"
PATCH[0]="001-null-pointer-fix.patch"
PATCH[1]="002-rdtscl.patch"
PATCH[2]="003-linux47.patch"
PATCH[3]="004-linux48.patch"
PATCH[4]="005-debian-fix-kernel-warnings.patch"
PATCH[5]="099-kernel-7.0-compat.patch"
PATCH[6]="100-kernel-7.1-compat.patch"
MAKE[0]="make -C \\\$kernel_source_dir M=\\\$dkms_tree/\\\$module/\\\$module_version/build objtool=/bin/true CC=clang LLVM=1 LD=ld.lld"
AUTOINSTALL="yes"
EOF

echo
echo "5) DKMS add/build/install"
dkms add -m "${MODNAME}" -v "${PKGVER}"
dkms build -m "${MODNAME}" -v "${PKGVER}" -k "${KVER}"
dkms install -m "${MODNAME}" -v "${PKGVER}" -k "${KVER}"

echo
echo "6) Blacklist de drivers en conflicto"
install -D -m 0644 "${here}/broadcom-wl-dkms.conf" /etc/modprobe.d/broadcom-wl-dkms.conf

echo
echo "7) Cargando el módulo wl"
modprobe wl

echo
echo "OK. Si 'modprobe wl' falla con 'Required key not available', tienes Secure Boot activado y debes desactivarlo o firmar el módulo."
