# F2FS kernel module Makefile
# Supports in-tree integration (fs/f2fs/ in Linux source) and out-of-tree builds (root Makefile).

f2fs-y		:= dir.o file.o inode.o namei.o hash.o super.o inline.o
f2fs-y		+= checkpoint.o gc.o data.o node.o segment.o recovery.o
f2fs-$(CONFIG_F2FS_STAT_FS) += debug.o
f2fs-$(CONFIG_F2FS_FS_XATTR) += xattr.o
f2fs-$(CONFIG_F2FS_FS_POSIX_ACL) += acl.o
f2fs-$(CONFIG_F2FS_IO_TRACE) += trace.o

# In-tree build
obj-$(CONFIG_F2FS_FS) += f2fs.o

# Out-of-tree fallback — include optional objects when Kconfig symbols are absent
ifeq ($(CONFIG_F2FS_FS),)
obj-m += f2fs.o
f2fs-y += debug.o xattr.o acl.o trace.o
endif
