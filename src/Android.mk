# Copyright 2005 The Android Open Source Project
#
# Android.mk for adb
#

LOCAL_PATH:= $(call my-dir)

#include $(LOCAL_PATH)/../platform_tools_tool_version.mk

adb_host_sanitize :=
adb_target_sanitize :=

ADB_COMMON_CFLAGS := \
    -Wall -Wextra -Werror \
    -Wno-unused-parameter \
    -Wno-missing-field-initializers \
    -Wvla \
    -DADB_VERSION="\"$(tool_version)\"" \

ADB_COMMON_posix_CFLAGS := \
    -Wexit-time-destructors \
    -Wthread-safety \

ADB_COMMON_linux_CFLAGS := \
    $(ADB_COMMON_posix_CFLAGS) \

ADB_COMMON_darwin_CFLAGS := \
    $(ADB_COMMON_posix_CFLAGS) \

# Define windows.h and tchar.h Unicode preprocessor symbols so that
# CreateFile(), _tfopen(), etc. map to versions that take wchar_t*, breaking the
# build if you accidentally pass char*. Fix by calling like:
#   std::wstring path_wide;
#   if (!android::base::UTF8ToWide(path_utf8, &path_wide)) { /* error handling */ }
#   CreateFileW(path_wide.c_str());
ADB_COMMON_windows_CFLAGS := \
    -DUNICODE=1 -D_UNICODE=1 \

# libadb
# =========================================================

# Much of adb is duplicated in bootable/recovery/minadb and fastboot. Changes
# made to adb rarely get ported to the other two, so the trees have diverged a
# bit. We'd like to stop this because it is a maintenance nightmare, but the
# divergence makes this difficult to do all at once. For now, we will start
# small by moving common files into a static library. Hopefully some day we can
# get enough of adb in here that we no longer need minadb. https://b/17626262

#LIB_OPENSSL_SRC_FILES := \
	../boringssl/src/crypto/base64/base64.cpp\
	../boringssl/src/crypto/evp/evp.cpp\
	../boringssl/src/crypto/bn/bn.cpp\
	../boringssl/src/crypto/rsa/rsa.cpp\
	../boringssl/src/crypto/pem/pem_pkey.cpp\
	../boringssl/src/crypto/pem/pem_all.cpp\
	../boringssl/src/crypto/x509/x_pubkey.cpp\
	../boringssl/src/crypto/bn/shift.cpp\
	../boringssl/src/crypto/bn/ctx.cpp\
	../boringssl/src/crypto/err/err.cpp\
	../boringssl/src/crypto/thread_pthread.cpp\
	../boringssl/src/crypto/asn1/tasn_utl.cpp\
	../boringssl/src/crypto/asn1/tasn_fre.cpp\
	../boringssl/src/crypto/stack/stack.cpp\
	../boringssl/src/crypto/asn1/asn1_lib.cpp\
	../boringssl/src/crypto/asn1/a_object.cpp\
	../boringssl/src/crypto/obj/obj.cpp

LIBBASE_SRC_FILES := \
	../lib/libcutils/socket_inaddr_any_server_unix.cpp \
	../lib/libcutils/sockets.cpp \
	../lib/libcutils/socket_local_server_unix.cpp \
	../lib/libcutils/socket_local_client_unix.cpp \
	../lib/libcutils/socket_network_client_unix.cpp \
	../lib/base/strings.cpp \
	../lib/base/file.cpp \
	../lib/base/stringprintf.cpp\
	../lib/base/logging.cpp\
	../lib/base/parsenetaddress.cpp \
	../src/sysdeps/posix/network.cpp \
	../src/sysdeps_unix.cpp\
	../src/client/usb_dispatch.cpp \
	./client/usb_linux.cpp\
	./adb_auth_host.cpp\
	./diagnose_usb.cpp \
	./transport_mdns.cpp\
	../mdnsresponder/mDNSShared/dnssd_clientstub.cpp\
	../mdnsresponder/mDNSShared/dnssd_ipc.cpp\
	../lib/libcrypto_utils/android_pubkey.cpp


LIBADB_SRC_FILES := \
    adb.cpp \
    adb_io.cpp \
    adb_listeners.cpp \
    adb_trace.cpp \
    adb_utils.cpp \
    fdevent.cpp \
    sockets.cpp \
    socket_spec.cpp \
    sysdeps/errno.cpp \
    transport.cpp \
    transport_local.cpp \
    transport_usb.cpp \

LIBADB_TEST_SRCS := \
    adb_io_test.cpp \
    adb_listeners_test.cpp \
    adb_utils_test.cpp \
    fdevent_test.cpp \
    socket_spec_test.cpp \
    socket_test.cpp \
    sysdeps_test.cpp \
    sysdeps/stat_test.cpp \
    transport_test.cpp \

LIBADB_CFLAGS := \
    $(ADB_COMMON_CFLAGS) \
    -fvisibility=hidden \

LIBADB_linux_CFLAGS := \
    $(ADB_COMMON_linux_CFLAGS) \

LIBADB_darwin_CFLAGS := \
    $(ADB_COMMON_darwin_CFLAGS) \

LIBADB_windows_CFLAGS := \
    $(ADB_COMMON_windows_CFLAGS) \

LIBADB_darwin_SRC_FILES := \
    sysdeps_unix.cpp \
    sysdeps/posix/network.cpp \
    client/usb_dispatch.cpp \
    client/usb_libusb.cpp \
    client/usb_osx.cpp \

LIBADB_linux_SRC_FILES := \
    sysdeps_unix.cpp \
    sysdeps/posix/network.cpp \
    client/usb_dispatch.cpp \
    client/usb_libusb.cpp \
    client/usb_linux.cpp \

LIBADB_windows_SRC_FILES := \
    sysdeps_win32.cpp \
    sysdeps/win32/errno.cpp \
    sysdeps/win32/stat.cpp \
    client/usb_windows.cpp \

LIBADB_TEST_windows_SRCS := \
    sysdeps/win32/errno_test.cpp \
    sysdeps_win32_test.cpp \

include $(CLEAR_VARS)
LOCAL_CLANG := true
LOCAL_MODULE := libadbd_usb
LOCAL_CFLAGS := $(LIBADB_CFLAGS) -DADB_HOST=0
LOCAL_SRC_FILES := daemon/usb.cpp

LOCAL_SANITIZE := $(adb_target_sanitize)

# Even though we're building a static library (and thus there's no link step for
# this to take effect), this adds the includes to our path.
LOCAL_STATIC_LIBRARIES := libcrypto_utils libcrypto libbase

include $(BUILD_STATIC_LIBRARY)

include $(CLEAR_VARS)
LOCAL_CLANG := true
LOCAL_MODULE := libadbd
LOCAL_CFLAGS := $(LIBADB_CFLAGS) -DADB_HOST=0
LOCAL_SRC_FILES := \
    $(LIBADB_SRC_FILES) \
    adbd_auth.cpp \
    jdwp_service.cpp \
    sysdeps/posix/network.cpp \

LOCAL_SANITIZE := $(adb_target_sanitize)

# Even though we're building a static library (and thus there's no link step for
# this to take effect), this adds the includes to our path.
LOCAL_STATIC_LIBRARIES := libcrypto_utils libcrypto libbase

LOCAL_WHOLE_STATIC_LIBRARIES := libadbd_usb

include $(BUILD_STATIC_LIBRARY)

include $(CLEAR_VARS)
LOCAL_MODULE := libadb
LOCAL_MODULE_HOST_OS := darwin linux windows
LOCAL_CFLAGS := $(LIBADB_CFLAGS) -DADB_HOST=1
LOCAL_CFLAGS_windows := $(LIBADB_windows_CFLAGS)
LOCAL_CFLAGS_linux := $(LIBADB_linux_CFLAGS)
LOCAL_CFLAGS_darwin := $(LIBADB_darwin_CFLAGS)
LOCAL_SRC_FILES := \
    $(LIBADB_SRC_FILES) \
    adb_auth_host.cpp \
    transport_mdns.cpp \

LOCAL_SRC_FILES_darwin := $(LIBADB_darwin_SRC_FILES)
LOCAL_SRC_FILES_linux := $(LIBADB_linux_SRC_FILES)
LOCAL_SRC_FILES_windows := $(LIBADB_windows_SRC_FILES)

LOCAL_SANITIZE := $(adb_host_sanitize)

# Even though we're building a static library (and thus there's no link step for
# this to take effect), this adds the includes to our path.
LOCAL_STATIC_LIBRARIES := libcrypto_utils libcrypto libbase libmdnssd
LOCAL_STATIC_LIBRARIES_linux := libusb
LOCAL_STATIC_LIBRARIES_darwin := libusb

LOCAL_C_INCLUDES_windows := development/host/windows/usb/api/
LOCAL_MULTILIB := first

#include $(BUILD_STATIC_LIBRARY)

include $(CLEAR_VARS)
LOCAL_CLANG := true
LOCAL_MODULE := adbd_test
LOCAL_CFLAGS := -DADB_HOST=0 $(LIBADB_CFLAGS)
LOCAL_SRC_FILES := \
    $(LIBADB_TEST_SRCS) \
    $(LIBADB_TEST_linux_SRCS) \
    shell_service.cpp \
    shell_service_protocol.cpp \
    shell_service_protocol_test.cpp \
    shell_service_test.cpp \

LOCAL_SANITIZE := $(adb_target_sanitize)
LOCAL_STATIC_LIBRARIES := libadbd libcrypto_utils libcrypto libusb libmdnssd
LOCAL_SHARED_LIBRARIES := liblog libbase libcutils
include $(BUILD_NATIVE_TEST)

# libdiagnose_usb
# =========================================================

include $(CLEAR_VARS)
LOCAL_MODULE := libdiagnose_usb
LOCAL_MODULE_HOST_OS := darwin linux windows
LOCAL_CFLAGS := $(LIBADB_CFLAGS)
LOCAL_SRC_FILES := diagnose_usb.cpp
# Even though we're building a static library (and thus there's no link step for
# this to take effect), this adds the includes to our path.
LOCAL_STATIC_LIBRARIES := libbase
#include $(BUILD_STATIC_LIBRARY)

# adb_test
# =========================================================

include $(CLEAR_VARS)
LOCAL_MODULE := adb_test
LOCAL_MODULE_HOST_OS := darwin linux windows
LOCAL_CFLAGS := -DADB_HOST=1 $(LIBADB_CFLAGS)  -std=c++11
LOCAL_CFLAGS_windows := $(LIBADB_windows_CFLAGS)
LOCAL_CFLAGS_linux := $(LIBADB_linux_CFLAGS)
LOCAL_CFLAGS_darwin := $(LIBADB_darwin_CFLAGS)
LOCAL_SRC_FILES := \
    $(LIBADB_TEST_SRCS) \
    adb_client.cpp \
    bugreport.cpp \
    bugreport_test.cpp \
    line_printer.cpp \
    services.cpp \
    shell_service_protocol.cpp \
    shell_service_protocol_test.cpp \

LOCAL_SRC_FILES_linux := $(LIBADB_TEST_linux_SRCS)
LOCAL_SRC_FILES_darwin := $(LIBADB_TEST_darwin_SRCS)
LOCAL_SRC_FILES_windows := $(LIBADB_TEST_windows_SRCS)
LOCAL_SANITIZE := $(adb_host_sanitize)
LOCAL_STATIC_LIBRARIES := \
    libadb \
    libbase \
    libcrypto_utils \
    libcrypto \
    libcutils \
    libdiagnose_usb \
    libmdnssd \
    libgmock_host \

LOCAL_STATIC_LIBRARIES_linux := libusb
LOCAL_STATIC_LIBRARIES_darwin := libusb

# Set entrypoint to wmain from sysdeps_win32.cpp instead of main
LOCAL_LDFLAGS_windows := -municode
LOCAL_LDLIBS_linux := -lrt -ldl -lpthread
LOCAL_LDLIBS_darwin := -framework CoreFoundation -framework IOKit -lobjc
LOCAL_LDLIBS_windows := -lws2_32 -luserenv
LOCAL_STATIC_LIBRARIES_windows := AdbWinApi

LOCAL_MULTILIB := first

####################################################
###  static library
include $(CLEAR_VARS)

# 我们将连接已编译好的my_blocks模块
LOCAL_MODULE    := openssl_static_libs

# 填写源文件名的时候，要把静态库或动态库的文件名填写完整。
# $(TARGET_ARCH_ABI)/ 表示将不同架构下的库文件存放到相应架构目录下
LOCAL_SRC_FILES := ../boringssl/./obj/local/arm64-v8a/libssl_static.a


# 用于预构建静态库（后面可被连接）
include $(PREBUILT_STATIC_LIBRARY)


LOCAL_MODULE    := crypt_static_libs

# 填写源文件名的时候，要把静态库或动态库的文件名填写完整。
# $(TARGET_ARCH_ABI)/ 表示将不同架构下的库文件存放到相应架构目录下
LOCAL_SRC_FILES := ../boringssl/./obj/local/arm64-v8a/libcrypto_static.a


# 用于预构建静态库（后面可被连接）
include $(PREBUILT_STATIC_LIBRARY)




#include $(BUILD_HOST_NATIVE_TEST)

# adb host tool
# =========================================================
include $(CLEAR_VARS)

LOCAL_LDLIBS_linux := -lrt -ldl -lpthread

LOCAL_LDLIBS_darwin := -lpthread -framework CoreFoundation -framework IOKit -framework Carbon -lobjc

# Use wmain instead of main
LOCAL_LDFLAGS_windows := -municode
LOCAL_LDLIBS_windows := -lws2_32 -lgdi32
LOCAL_STATIC_LIBRARIES_windows := AdbWinApi
LOCAL_REQUIRED_MODULES_windows := AdbWinApi AdbWinUsbApi

LOCAL_SRC_FILES := \
	$(LIBADB_SRC_FILES)\
	$(LIBBASE_SRC_FILES)\
    adb_client.cpp \
    bugreport.cpp \
    client/main.cpp \
    console.cpp \
    commandline.cpp \
    file_sync_client.cpp \
    line_printer.cpp \
    services.cpp \
    shell_service_protocol.cpp \

LOCAL_CFLAGS += \
    $(ADB_COMMON_CFLAGS) \
    -D_GNU_SOURCE \
    -DDONT_USE_LIBUSB \
    -DNOT_HAVE_SA_LEN \
    -DADB_HOST=1 \
	-I../lib/base/include\
	-std=c++11 -O3 \
	-I../lib/libcutils/include\
	-I../include \
	-I../lib/libcrypto_utils/include\
	-I../mdnsresponder/mDNSShared \
	-I../boringssl/src/include
#-I/disk/B/moon/adb/arm64/openssl-1.0.1e/include	
#-I/usr/local/ssl/android-24/include\
#	-I/home/wangjf/Android/Sdk/ndk-bundle/sysroot/usr/include
LOCAL_CFLAGS_windows := \
    $(ADB_COMMON_windows_CFLAGS)

LOCAL_CFLAGS_linux := \
    $(ADB_COMMON_linux_CFLAGS) \

LOCAL_CFLAGS_darwin := \
    $(ADB_COMMON_darwin_CFLAGS) \
    -Wno-sizeof-pointer-memaccess -Wno-unused-parameter \
#LOCAL_CLANG := true
LOCAL_MODULE := adb
LOCAL_MODULE_TAGS := debug
LOCAL_MODULE_HOST_OS := darwin linux windows

LOCAL_SANITIZE := $(adb_host_sanitize)
#LOCAL_STATIC_LIBRARIES := \
    libadb \
    libbase \
    libcrypto_utils \
    libcrypto \
    libdiagnose_usb \
    liblog \
    libmdnssd \

LOCAL_STATIC_LIBRARIES := openssl_static_libs crypt_static_libs

# Don't use libcutils on Windows.
LOCAL_STATIC_LIBRARIES_darwin := libcutils
LOCAL_STATIC_LIBRARIES_linux := libcutils

LOCAL_STATIC_LIBRARIES_darwin += libusb
LOCAL_STATIC_LIBRARIES_linux += libusb

LOCAL_LDLIBS += -llog
APP_STL := stlport_static
LOCAL_CXX_STL := libc++_static

# Don't add anything here, we don't want additional shared dependencies
# on the host adb tool, and shared libraries that link against libc++
# will violate ODR
LOCAL_SHARED_LIBRARIES :=

include $(BUILD_EXECUTABLE)

$(call dist-for-goals,dist_files sdk win_sdk,$(LOCAL_BUILT_MODULE))
ifdef HOST_CROSS_OS
# Archive adb.exe for win_sdk build.
$(call dist-for-goals,win_sdk,$(ALL_MODULES.host_cross_adb.BUILT))
endif


# adbd device daemon
# =========================================================

include $(CLEAR_VARS)

LOCAL_CLANG := true

LOCAL_SRC_FILES := \
    daemon/main.cpp \
    daemon/mdns.cpp \
    services.cpp \
    file_sync_service.cpp \
    framebuffer_service.cpp \
    remount_service.cpp \
    set_verity_enable_state_service.cpp \
    shell_service.cpp \
    shell_service_protocol.cpp \

LOCAL_CFLAGS := \
    $(ADB_COMMON_CFLAGS) \
    $(ADB_COMMON_linux_CFLAGS) \
    -DADB_HOST=0 \
    -D_GNU_SOURCE \
    -Wno-deprecated-declarations \

LOCAL_CFLAGS += -DALLOW_ADBD_NO_AUTH=$(if $(filter userdebug eng,$(TARGET_BUILD_VARIANT)),1,0)

ifneq (,$(filter userdebug eng,$(TARGET_BUILD_VARIANT)))
LOCAL_CFLAGS += -DALLOW_ADBD_DISABLE_VERITY=1
LOCAL_CFLAGS += -DALLOW_ADBD_ROOT=1
endif

LOCAL_MODULE := adbd

LOCAL_FORCE_STATIC_EXECUTABLE := true
LOCAL_MODULE_PATH := $(TARGET_ROOT_OUT_SBIN)
LOCAL_UNSTRIPPED_PATH := $(TARGET_ROOT_OUT_SBIN_UNSTRIPPED)

LOCAL_SANITIZE := $(adb_target_sanitize)
LOCAL_STRIP_MODULE := keep_symbols
LOCAL_STATIC_LIBRARIES := \
    libadbd \
    libavb_user \
    libbase \
    libbootloader_message \
    libfs_mgr \
    libfec \
    libfec_rs \
    libselinux \
    liblog \
    libext4_utils \
    libsquashfs_utils \
    libcutils \
    libbase \
    libcrypto_utils \
    libcrypto \
    libminijail \
    libmdnssd \
    libdebuggerd_handler \

#include $(BUILD_EXECUTABLE)

# adb integration test
# =========================================================
$(call dist-for-goals,sdk,$(ALL_MODULES.adb_integration_test_adb.BUILT))
$(call dist-for-goals,sdk,$(ALL_MODULES.adb_integration_test_device.BUILT))

include $(call first-makefiles-under,$(LOCAL_PATH))
