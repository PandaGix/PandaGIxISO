;;; This is an operating system configuration
;;; used by the PandaGixImage develper preview release.
;;; BambooGeek@PandaGix
;;;
;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2014, 2015, 2016, 2017, 2018, 2019, 2020, 2021 Ludovic Courtès <ludo@gnu.org>
;;; Copyright © 2015 Mark H Weaver <mhw@netris.org>
;;; Copyright © 2016 Andreas Enge <andreas@enge.fr>
;;; Copyright © 2017 Marius Bakke <mbakke@fastmail.com>
;;; Copyright © 2017, 2019 Tobias Geerinckx-Rice <me@tobias.gr>
;;; Copyright © 2020 Florian Pelz <pelzflorian@pelzflorian.de>
;;; Copyright © 2020 Efraim Flashner <efraim@flashner.co.il>
;;; Copyright © 2021 BambooGeek <nju@git.nju.edu.cn>
;;;
;;; This file is NOT part of GNU Guix.
;;;
;;; This file is free software; you can redistribute it and/or modify it
;;; under the terms of the GNU General Public License as published by
;;; the Free Software Foundation; either version 3 of the License, or (at
;;; your option) any later version.
;;;
;;; This file is distributed in the hope that it will be useful, but
;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License.
;;; If not, see <http://www.gnu.org/licenses/>.

(define-module (gix system live)
  #:use-module (gnu)
  #:use-module (gnu system)
  #:use-module (gnu bootloader u-boot)
  #:use-module (guix gexp)
  #:use-module (guix store)
  #:use-module (guix monads)
  #:use-module (guix modules)
  #:use-module ((guix packages) #:select (package-version))
  #:use-module ((guix store) #:select (%store-prefix))
  #:use-module (gnu installer)
  #:use-module (gnu system locale)
  #:use-module (gnu services avahi)
  #:use-module (gnu services dbus)
  #:use-module (gnu services networking)
  #:use-module (gnu services shepherd)
  #:use-module (gnu services ssh)
  #:use-module (gnu packages admin)
  #:use-module (gnu packages bash)
  #:use-module (gnu packages bootloaders)
  #:use-module (gnu packages certs)
  #:use-module (gnu packages compression)
  #:use-module (gnu packages fonts)
  #:use-module (gnu packages fontutils)
  #:use-module (gnu packages guile)
  #:use-module (gnu packages linux) ; might conflict with (nongnu packages linux)
  #:use-module (gnu packages package-management)
  #:use-module (gnu packages texinfo)
  #:use-module (gnu packages xorg)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-26)

  ;;;;added for non-libre linux
  #:use-module (nongnu packages linux) ; channel inferior
  #:use-module (nongnu system linux-initrd)
  #:use-module (srfi srfi-1)
  #:use-module (guix channels) 
  #:use-module (guix inferior)
  #:use-module (gnu packages gnome)
  #:use-module (gnu packages gnome-xyz)
  #:use-module (gnu packages disk)
  #:use-module (gnu packages chromium)
  #:use-module (gnu packages version-control)
  #:use-module (gnu packages curl)
  #:use-module (gnu packages perl)
  #:use-module (gnu packages ibus)
  #:use-module (gnu packages audio)
  #:use-module (gnu packages file-systems)
  #:use-module (gnu packages xdisorg)
  
  ;;(use-service-modules desktop networking ssh xorg)
  #:use-module (gnu services base)
  #:use-module (gnu services desktop)
  #:use-module (gnu services xorg)

  #:export (live-os)
) ; end of (define module


(define %installation-node-names
  ;; Translated name of the "System Installation" node of the manual.  Ideally
  ;; we'd extract it from the 'guix-manual' gettext domain, but that one is
  ;; usually not available at run time, hence this hack.
  '(("de" . "Systeminstallation")
    ("en" . "System Installation")
    ("es" . "Instalación del sistema")
    ("fr" . "Installation du système")
    ("ru" . "Установка системы")))

(define (log-to-info tty user)
  "Return a script that spawns the Info reader on the right section of the
manual."
  (program-file "log-to-info"
                #~(let* ((tty      (open-file #$(string-append "/dev/" tty)
                                              "r0+"))
                         (locale   (cadr (command-line)))
                         (language (string-take locale
                                                (string-index locale #\_)))
                         (infodir  "/run/current-system/profile/share/info")
                         (per-lang (string-append infodir "/guix." language
                                                  ".info.gz"))
                         (file     (if (file-exists? per-lang)
                                       per-lang
                                       (string-append infodir "/guix.info")))
                         (node     (or (assoc-ref '#$%installation-node-names
                                                  language)
                                       "System Installation")))
                    (redirect-port tty (current-output-port))
                    (redirect-port tty (current-error-port))
                    (redirect-port tty (current-input-port))

                    (let ((pw (getpwnam #$user)))
                      (setgid (passwd:gid pw))
                      (setuid (passwd:uid pw)))

                    ;; 'gunzip' is needed to decompress the doc.
                    (setenv "PATH" (string-append #$gzip "/bin"))

                    ;; Change this process' locale so that command-line
                    ;; arguments to 'info' are properly encoded.
                    (catch #t
                      (lambda ()
                        (setlocale LC_ALL locale)
                        (setenv "LC_ALL" locale))
                      (lambda _
                        ;; Sometimes LOCALE itself is not available.  In that
                        ;; case pick the one UTF-8 locale that's known to work
                        ;; instead of failing.
                        (setlocale LC_ALL "en_US.utf8")
                        (setenv "LC_ALL" "en_US.utf8")))

                    (execl #$(file-append info-reader "/bin/info")
                           "info" "-d" infodir "-f" file "-n" node))))

(define (documentation-shepherd-service tty)
  (list (shepherd-service
         (provision (list (symbol-append 'term- (string->symbol tty))))
         (requirement '(user-processes host-name udev virtual-terminal))
         (start #~(lambda* (#:optional (locale "en_US.utf8"))
                    (fork+exec-command
                     (list #$(log-to-info tty "documentation") locale)
                     #:environment-variables
                     `("GUIX_LOCPATH=/run/current-system/locale"
                       "TERM=linux"))))
         (stop #~(make-kill-destructor)))))

(define %documentation-users
  ;; User account for the Info viewer.
  (list (user-account (name "documentation")
                      (system? #t)
                      (group "nogroup")
                      (home-directory "/var/empty"))))

(define documentation-service-type
  ;; Documentation viewer service.
  (service-type (name 'documentation)
                (extensions
                 (list (service-extension shepherd-root-service-type
                                          documentation-shepherd-service)
                       (service-extension account-service-type
                                          (const %documentation-users))))
                (description "Run the Info reader on a tty.")))


(define %backing-directory
  ;; Sub-directory used as the backing store for copy-on-write.
  "/tmp/gix-inst")

(define cow-store-service-type
  (shepherd-service-type
   'cow-store
   (lambda _
     (define (import-module? module)
       ;; Since we don't use deduplication support in 'populate-store', don't
       ;; import (guix store deduplication) and its dependencies, which
       ;; includes Guile-Gcrypt.
       (and (guix-module-name? module)
            (not (equal? module '(guix store deduplication)))))

     (shepherd-service
      (requirement '(root-file-system user-processes))
      (provision '(cow-store))
      (documentation
       "Make the store copy-on-write, with writes going to \
the given target.")

      ;; This is meant to be explicitly started by the user.
      (auto-start? #f)

      (modules `((gnu build install)
                 ,@%default-modules))
      (start
       (with-imported-modules (source-module-closure
                               '((gnu build install))
                               #:select? import-module?)
         #~(case-lambda
             ((target)
              (mount-cow-store target #$%backing-directory)
              target)
             (else
              ;; Do nothing, and mark the service as stopped.
              #f))))
      (stop #~(lambda (target)
                ;; Delete the temporary directory, but leave everything
                ;; mounted as there may still be processes using it since
                ;; 'user-processes' doesn't depend on us.  The 'user-file-systems'
                ;; service will unmount TARGET eventually.
                (delete-file-recursively
                 (string-append target #$%backing-directory))))))
   (description "Make the store copy-on-write, with writes going to \
the given target.")))

(define (cow-store-service)
  "Return a service that makes the store copy-on-write, such that writes go to
the user's target storage device rather than on the RAM disk."
  ;; See <http://bugs.gnu.org/18061> for the initial report.
  (service cow-store-service-type 'mooooh!))

(define %nscd-minimal-caches
  ;; Minimal in-memory caching policy for nscd.
  (list (nscd-cache (database 'hosts)
                    (positive-time-to-live (* 3600 12))

                    ;; Do not cache lookup failures at all since they are
                    ;; quite likely (for instance when someone tries to ping a
                    ;; host before networking is functional.)
                    (negative-time-to-live 0)

                    (persistent? #f)
                    (max-database-size (* 5 (expt 2 20)))))) ;5 MiB


;; These define a service to load the uvesafb kernel module with the
;; appropriate options.  The GUI installer needs it when the machine does not
;; support Kernel Mode Setting.  Otherwise kmscon is missing /dev/fb0.
(define (uvesafb-shepherd-service _)
  (list (shepherd-service
         (documentation "Load the uvesafb kernel module if needed.")
         (provision '(maybe-uvesafb))
         (requirement '(file-systems))
         (start #~(lambda ()
                    ;; uvesafb is only supported on x86 and x86_64.
                    (or (not (and (string-suffix? "linux-gnu" %host-type)
                                  (or (string-prefix? "x86_64" %host-type)
                                      (string-prefix? "i686" %host-type))))
                        (file-exists? "/dev/fb0")
                        (invoke #+(file-append kmod "/bin/modprobe")
                                "uvesafb"
                                (string-append "v86d=" #$v86d "/sbin/v86d")
                                "mode_option=1024x768"))))
         (respawn? #f)
         (one-shot? #t))))

(define uvesafb-service-type
  (service-type
   (name 'uvesafb)
   (extensions
    (list (service-extension shepherd-root-service-type
                             uvesafb-shepherd-service)))
   (description
    "Load the @code{uvesafb} kernel module with the right options.")
   (default-value #t)))



;;; os related

(define kernel-5-4-98-pinned
    (let* (
            (channels (list 
            (channel
                (name 'guix)
                (url "https://git.nju.edu.cn/nju/guix.git")
                (commit "6941dbf958a2294e0a058af3498df9c46a6a1e50")
                (introduction
		(make-channel-introduction
          	"9edb3f66fd807b096b48283debdcddccfea34bad" ; from guix/channels.scm, said 20200526
          	(openpgp-fingerprint
           	"BBB0 2DDF 2CEA F6A8 0D1D  E643 A2A0 6DF2 A33A 54FA" ; from guix/channels.scm
		)))) ; end of this (channel
            (channel
                (name 'nonguix)
                (url "https://git.nju.edu.cn/nju/nonguix.git")
                (commit "1d58ea1acadba57b34669c8a3f3d9f0de8d339b5")
                (introduction
		(make-channel-introduction
          	"897c1a470da759236cc11798f4e0a5f7d4d59fbc"
          	(openpgp-fingerprint
           	"2A39 3FFF 68F4 EF7A 3D29  12AF 6F51 20A0 22FB B2D5"
		)))) ; end of this (channel
            )) ; end of (channels (list
          (inferior (inferior-for-channels channels)) ) ;(
      ;;    (first (list linux-lts)) )) 
      ;; do NOT lookup-inferior for "linux-lts", since it is an alias to "linux"
      ;; and does not have its own version number
      (first (lookup-inferior-packages inferior "linux" "5.4.98")) ) )


(define live-os
;;(use-modules (gnu) (nongnu packages linux) (nongnu system linux-initrd) (srfi srfi-1) (guix channels)  (guix inferior) )
;;(use-service-modules desktop networking ssh xorg)
(operating-system
  ;; NonGuix
  ;;(kernel linux-lts)
  (kernel kernel-5-4-98-pinned) ; end of (kernel 
  ;;(initrd microcode-initrd) ; no initrd in iso-live
  (firmware (list linux-firmware)) 
  (kernel-arguments '("quiet")) ; stripped from installation-os

  ;; Guix
  (locale "en_US.utf8") ; using en_US.utf8, as zh_CN causing problem at gdm login screen and console
  (timezone "Asia/Shanghai") ; UTC
  (keyboard-layout (keyboard-layout "cn")) ; us
  (host-name "PandaGix")
  (label (string-append "PandaGix Live " (package-version guix)))
    (users (cons*
        (user-account
                  (name "guest")
                  (group "users")
                  (supplementary-groups '("wheel")) ; allow use of sudo
                  (password "")
                  (comment "Guest of PandaGix"))
        (user-account
                  (name "panda")
                  (group "users")
                  (supplementary-groups '("wheel" "netdev" "audio" "video")) ; allow use of sudo by in wheel
                  (password "gix")
                  (comment "name:panda passwd:gix"))
        %base-user-accounts))
  (services
    (append
      (list (service openssh-service-type)
            (service cow-store-service-type 'mooooh!) ; service cow-store for installation
            ;;(service dhcp-client-service-type) ; change base-services with dhcp-client-service
            (service gnome-desktop-service-type) ; use gnome-desktop
            ;;(service xfce-desktop-service-type)
            ;;(service mate-desktop-service-type)
            (set-xorg-configuration (xorg-configuration
              (keyboard-layout keyboard-layout)))
      )
      (modify-services %desktop-services ; change base-services with dhcp-client-service
        (guix-service-type config => 
          (guix-configuration (inherit config)
            (substitute-urls (append (list
              "https://mirror.sjtu.edu.cn/guix" ; use in china
            ) %default-substitute-urls))
            )))
    )) ; end of (services)
    ;; We don't need setuid programs, except for 'passwd', which can be handy
    ;; if one is to allow remote SSH login to the machine being installed.
  (setuid-programs (list (file-append shadow "/bin/passwd")))
  (pam-services   ; Explicitly allow for empty passwords.
      (base-pam-services #:allow-empty-passwords? #t))
  (packages (append (list
        nss-certs glibc grub git curl perl util-linux
        fuse dosfstools jfsutils e2fsprogs lvm2-static btrfs-progs zfs ntfs-3g apfs-fuse exfatprogs
        fontconfig font-dejavu font-gnu-unifont font-google-noto
        xorg-server gdm gnome gnome-shell gnome-desktop
        ibus libpinyin dconf ibus-libpinyin
        ungoogled-chromium evolution 
        gnome-bluetooth gnome-tweaks dconf-editor gnome-backgrounds
        gnome-multi-writer brasero gparted 
        gnome-mines gnome-sudoku gnome-klotski ;gnome-music 
        gnome-shell-extension-appindicator   gnome-shell-extension-clipboard-indicator
        gnome-shell-extension-topicons-redux gnome-shell-extension-gsconnect
        gnome-shell-extension-dash-to-dock   gnome-shell-extension-dash-to-panel
        gnome-shell-extension-hide-app-icon  gnome-shell-extension-noannoyance
        gnome-shell-extension-paperwm 
        ldacbt bluez-alsa
        xf86-video-dummy xf86-video-amdgpu xf86-video-ati xf86-video-nv xf86-video-intel
        xf86-input-evdev xf86-input-void xf86-input-synaptics xf86-input-mouse xf86-input-keyboard 
        xf86-input-wacom xf86-input-joystick 
        )%base-packages-disk-utilities %base-packages)) ; end of (packages

  (bootloader (bootloader-configuration
              (bootloader grub-bootloader)
              (target "/dev/sda")))
  (file-systems
     ;; Note: the disk image build code overrides this root file system with the appropriate one.
     (cons* 
            (file-system
              (mount-point "/")
              (device (file-system-label "PandaGixImage"))
              (type "ext4"))
            ;;  (see <http://bugs.gnu.org/23056>).  We keep this for overlayfs to be on the safe side.
            (file-system
              (mount-point "/tmp") ; Make /tmp a tmpfs instead of keeping the overlayfs.
              (device "none")             	; This originally was used for unionfs because FUSE creates 
              (type "tmpfs")              	;  '.fuse_hiddenXYZ' files for each open file, 
              (check? #f))                	; and this confuses Guix's test suite, for instance
            %base-file-systems))
); end of (operating system
) ; end of (define live-os

;; Return the default os here so 'guix system' can consume it directly.
;; installation-os
live-os
