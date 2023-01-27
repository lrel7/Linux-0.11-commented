	.code16
# rewrite with AT&T syntax by falcon <wuzhangjin@gmail.com> at 081012
#
# SYS_SIZE is the number of clicks (16 bytes) to be loaded.
# 0x3000 is 0x30000 bytes = 196kB, more than enough for current
# versions of linux
#
# system模块长度，单位是节（16字节为1节）
	.equ SYSSIZE, 0x3000
#
#	bootsect.s		(C) 1991 Linus Torvalds
#
# bootsect.s is loaded at 0x7c00 by the bios-startup routines, and moves
# iself out of the way to address 0x90000, and jumps there.
#
# It then loads 'setup' directly after itself (0x90200), and the system
# at 0x10000, using BIOS interrupts. 
#
# NOTE! currently system is at most 8*65536 bytes long. This should be no
# problem, even in the future. I want to keep it simple. This 512 kB
# kernel size should be enough, especially as this doesn't contain the
# buffer cache as in minix
#
# The loader has been made as simple as possible, and continuos
# read errors will result in a unbreakable loop. Reboot by hand. It
# loads pretty fast by getting whole sectors at a time whenever possible.

# .global(或.globl)定义随后的标识符是外部的或全局的
	.global _start, begtext, begdata, begbss, endtext, enddata, endbss
# .text定义当前代码段
	.text
	begtext:
# .data定义数据段
	.data
	begdata:
# .bss定义未初始化数据
	.bss
	begbss:
	.text

# setup的扇区数
	.equ SETUPLEN, 4		# nr of setup-sectors
# bootsect的原始地址
	.equ BOOTSEG, 0x07c0		# original address of boot-sector
# bootsect此后将自己移到这里
	.equ INITSEG, 0x9000		# we move boot here - out of the way
# setup从这里开始
	.equ SETUPSEG, 0x9020		# setup starts here
# system加载到这里
	.equ SYSSEG, 0x1000		# system loaded at 0x10000 (65536).
# 停止加载的地址
	.equ ENDSEG, SYSSEG + SYSSIZE	# where to stop loading

# ROOT_DEV:	0x000 - same type of floppy as boot.
#		0x301 - first partition on first drive etc
#
##和源码不同，源码中是0x306 第2块硬盘的第一个分区
#
# ROOT_DEV是设备号，指定根文件系统的位置
# 命名方式：主设备号*256 + 次设备号
# 主设备号：1-内存 2-磁盘 3-硬盘 4-ttyx 5-并行口 6-非命名管道
# 0x300-第一个磁盘，0x301-第一个盘的第一个分区，...，0x304-第一给盘的第四个分区
# 0x305-第二个磁盘，0x306-第二个盘的第一个分区，...
	.equ ROOT_DEV, 0x301
	ljmp    $BOOTSEG, $_start
_start:
# 将自身从0x07c0移到0x9000
# 一般来说mov指令格式是mov dst src,但下面好像反过来了
# 将ds段寄存器设置为0x7C0(BOOTSEG)
# 8086不允许直接将数据送入段寄存器，因此需要ax寄存器做辅助
	mov	$BOOTSEG, %ax	# 将0x07c0处的值复制到ax寄存器
	mov	%ax, %ds		# 将ax寄存器的值复制到ds段寄存器
#将es段寄存器设置为0x900
	mov	$INITSEG, %ax	# 将ax寄存器的值(即ds寄存器的值)复制到0x9000处	
	mov	%ax, %es		# 将ax寄存器的值复制到es段寄存器
# 设置移动计数值256字
	mov	$256, %cx		
# 将si寄存器设为0 源地址ds:si = 0x07C0:0x0000(ds是段地址，si是偏移地址)
	sub	%si, %si		
# 将di寄存器设为0 目标地址es:si = 0x9000:0x0000
	sub	%di, %di		
# 重复执行并递减cx的值
	rep					
# 从内存[si]处移动cx个字到[di]处
	movsw				
# 段间跳转，INITSEG指出跳转到的段地址，go是偏移地址
	ljmp	$INITSEG, $go	

# 此时CPU已移动到0x90000处执行代码
# 下面设置段寄存器DS,ES,都置成移动后代码所在的段处(0x9000)
go:	mov	%cs, %ax		
	mov	%ax, %ds
	mov	%ax, %es
# 设置堆栈寄存器SS和SP
# put stack at 0x9ff00.
	mov	%ax, %ss
	mov	$0xFF00, %sp		# arbitrary value >>512

# load the setup-sectors directly after the bootblock.
# Note that 'es' is already set up.
# 加载setup模块
# 利用BIOS中断INT 0x13将setup从地盘第二个扇区读到0x90200
#
##ah=0x02 读磁盘扇区到内存	al＝需要独出的扇区数量
##ch=磁道(柱面)号的低八位   cl＝开始扇区(位0-5),磁道号高2位(位6－7)
##dh=磁头号					dl=驱动器号(硬盘则7要置位)
##es:bx ->指向数据缓冲区；如果出错则CF标志置位,ah中是出错码
#
load_setup:
	mov	$0x0000, %dx		# drive 0, head 0
	mov	$0x0002, %cx		# sector 2, track 0
	mov	$0x0200, %bx		# 偏移量 = 512, in INITSEG段(0x9000)
	.equ    AX, 0x0200+SETUPLEN
	mov     $AX, %ax		# service 2, nr of sectors
	int	$0x13				# read it
	jnc	ok_load_setup		# ok - continue
# 出错，复位驱动器并重试
	mov	$0x0000, %dx
	mov	$0x0000, %ax		# reset the diskette
	int	$0x13
	jmp	load_setup

ok_load_setup:

# Get disk drive parameters, specifically nr of sectors/track

	mov	$0x00, %dl			# dl-驱动器号
	mov	$0x0800, %ax		# AX=0x0800，则AH=8 is get drive parameters
	int	$0x13
	mov	$0x00, %ch
	#seg cs					# 表示下一条语句的操作数在cs段寄存器所指的段中(但本程序代码和数据都在同一个段内，所以这条指令不需要)
	mov	%cx, %cs:sectors+0	# %cs means sectors is in %cs
	mov	$INITSEG, %ax		# 上面取磁盘参数中断改掉了es的值，这里重新设置
	mov	%ax, %es

# Print some inane message
# 显示信息："'Loading system...'回车换行"
# BIOS中断0x10
# 功能号：ax 输入：bx-页号
# 返回：ch-扫描开始线 cl-扫描结束线 dh-行号 dl-列号
	mov	$0x03, %ah			# 中断功能号0x03,读光标位置,返回在dx(dh+dl)中，供显示串用
	xor	%bh, %bh			# 输入：页号
	int	$0x10				
	
	mov	$30, %cx			# 共显示24个字符(这个30是八进制吗)
	mov	$0x0007, %bx		# page 0, attribute 7 (normal)
	#lea	msg1, %bp
	mov     $msg1, %bp 		# es:bp指向要显示的字符串(msg1定义在末尾)
	mov	$0x1301, %ax		# 中断功能号0x13,显示字符串; al=0x01表示使用bl中的属性值(光标停在字符串结尾处)
	int	$0x10

# ok, we've written the message, now
# we want to load the system (at 0x10000)
# 现在将system模块加载到0x10000处

	mov	$SYSSEG, %ax	# 将es设置为system的段地址(0x10000)
	mov	%ax, %es		# segment of 0x010000
	call	read_it		# 读取磁盘上的system模块(es作为输入参数)
	call	kill_motor  # 关闭驱动器马达，得知驱动器状态

# After that we check which root-device to use. If the device is
# defined (#= 0), nothing is done and the given device is used.
# Otherwise, either /dev/PS0 (2,28) or /dev/at0 (2,8), depending
# on the number of sectors that the BIOS reports currently.

	#seg cs
	mov	%cs:root_dev+0, %ax
	cmp	$0, %ax
	jne	root_defined
	#seg cs
	mov	%cs:sectors+0, %bx
	mov	$0x0208, %ax		# /dev/ps0 - 1.2Mb
	cmp	$15, %bx
	je	root_defined
	mov	$0x021c, %ax		# /dev/PS0 - 1.44Mb
	cmp	$18, %bx
	je	root_defined
undef_root:
	jmp undef_root
root_defined:
	#seg cs
	mov	%ax, %cs:root_dev+0

# after that (everyting loaded), we jump to
# the setup-routine loaded directly after
# the bootblock:

	ljmp	$SETUPSEG, $0

# This routine loads the system at address 0x10000, making sure
# no 64kB boundaries are crossed. We try to load it as fast as
# possible, loading whole tracks whenever we can.
#
# in:	es - starting address segment (normally 0x1000)
#
sread:	.word 1+ SETUPLEN	# sectors read of current track
head:	.word 0			# current head
track:	.word 0			# current track

read_it:
	mov	%es, %ax
	test	$0x0fff, %ax
die:	jne 	die			# es must be at 64kB boundary
	xor 	%bx, %bx		# bx is starting address within segment
rp_read:
	mov 	%es, %ax
 	cmp 	$ENDSEG, %ax		# have we loaded all yet?
	jb	ok1_read
	ret
ok1_read:
	#seg cs
	mov	%cs:sectors+0, %ax
	sub	sread, %ax
	mov	%ax, %cx
	shl	$9, %cx
	add	%bx, %cx
	jnc 	ok2_read
	je 	ok2_read
	xor 	%ax, %ax
	sub 	%bx, %ax
	shr 	$9, %ax
ok2_read:
	call 	read_track
	mov 	%ax, %cx
	add 	sread, %ax
	#seg cs
	cmp 	%cs:sectors+0, %ax
	jne 	ok3_read
	mov 	$1, %ax
	sub 	head, %ax
	jne 	ok4_read
	incw    track 
ok4_read:
	mov	%ax, head
	xor	%ax, %ax
ok3_read:
	mov	%ax, sread
	shl	$9, %cx
	add	%cx, %bx
	jnc	rp_read
	mov	%es, %ax
	add	$0x1000, %ax
	mov	%ax, %es
	xor	%bx, %bx
	jmp	rp_read

read_track:
	push	%ax
	push	%bx
	push	%cx
	push	%dx
	mov	track, %dx
	mov	sread, %cx
	inc	%cx
	mov	%dl, %ch
	mov	head, %dx
	mov	%dl, %dh
	mov	$0, %dl
	and	$0x0100, %dx
	mov	$2, %ah
	int	$0x13
	jc	bad_rt
	pop	%dx
	pop	%cx
	pop	%bx
	pop	%ax
	ret
bad_rt:	mov	$0, %ax
	mov	$0, %dx
	int	$0x13
	pop	%dx
	pop	%cx
	pop	%bx
	pop	%ax
	jmp	read_track

#/*
# * This procedure turns off the floppy drive motor, so
# * that we enter the kernel in a known state, and
# * don't have to worry about it later.
# */
kill_motor:
	push	%dx
	mov	$0x3f2, %dx
	mov	$0, %al
	outsb
	pop	%dx
	ret

sectors:
	.word 0

msg1:
	.byte 13,10
	.ascii "IceCityOS is booting ..."
	.byte 13,10,13,10

	.org 508
root_dev:
	.word ROOT_DEV
boot_flag:
	.word 0xAA55
	
	.text
	endtext:
	.data
	enddata:
	.bss
	endbss:
