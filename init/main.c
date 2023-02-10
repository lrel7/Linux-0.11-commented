/*
 *  linux/init/main.c
 *
 *  (C) 1991  Linus Torvalds
 */

#define __LIBRARY__ // 为了包括定义在unistd.h中的内嵌汇编代码等信息
#include <unistd.h> // 标准符号常数与类型文件,由于定义了_LIBRARY_,所以还包含系统调用号和内嵌汇编代码等
#include <time.h> // 时间类型头文件

/*
 * we need this inline - forking from kernel space will result
 * in NO COPY ON WRITE (!!!), until an execve is executed. This
 * is no problem, but for the stack. This is handled by not letting
 * main() use the stack at all after fork(). Thus, no function
 * calls - which means inline code for fork too, as otherwise we
 * would use the stack upon exit from 'fork()'.
 *
 * Actually only pause and fork are needed inline, so that there
 * won't be any messing with the stack from main(), but we define
 * some others too.
 */
static inline fork(void) __attribute__((always_inline));
static inline pause(void) __attribute__((always_inline));
// _syscall0()是unistd.h中的内嵌宏代码,0-无参数,1-1个参数
static inline _syscall0(int,fork) // fork()
static inline _syscall0(int,pause) // pause()
static inline _syscall1(int,setup,void *,BIOS) // int setup(void* BIOS)
static inline _syscall0(int,sync)

#include <linux/tty.h> // 有关tty_io,串行通信
#include <linux/sched.h> // 调度程序
#include <linux/head.h> // 段描述符,选择符常量
#include <asm/system.h> // 以宏的形式定义了许多有关设置或修改描述符/中断门等的嵌入式汇编子程序
#include <asm/io.h> // 以宏的嵌入汇编程序形式定义对io端口操作的函数

#include <stddef.h> // 标准定义
#include <stdarg.h> // 标准参数
#include <unistd.h> 
#include <fcntl.h> // 文件控制
#include <sys/types.h> // 定义了基本的系统数据类型

#include <linux/fs.h> // 文件系统

static char printbuf[1024]; // 内核显示信息的缓存

extern int vsprintf(); // 格式化输出到一字符串中
extern void init(void); // 初始化,定义见后
extern void blk_dev_init(void); // 块设备初始化
extern void chr_dev_init(void); // 字符设备初始化
extern void hd_init(void); // 硬盘初始化
extern void floppy_init(void); // 软驱初始化
extern void mem_init(long start, long end); // 内存管理初始化
extern long rd_init(long mem_start, int length); // 虚拟盘初始化
extern long kernel_mktime(struct tm * tm); // 系统开机启动时间
extern long startup_time; // 内核启动时间

/*
 * This is set up by the setup-routine at boot-time
 */
#define EXT_MEM_K (*(unsigned short *)0x90002) // 1MB以后的扩展内存大小(KB)
#define DRIVE_INFO (*(struct drive_info *)0x90080) // 硬盘参数表的32字节内容
#define ORIG_ROOT_DEV (*(unsigned short *)0x901FC) // 根文件目录所在设备号

/*
 * Yeah, yeah, it's ugly, but I cannot find how to do this correctly
 * and this seems to work. I anybody has more info on the real-time
 * clock I'd be interested. Most of this was trial and error, and some
 * bios-listing reading. Urghh.
 */

// 读取CMOS实时时钟信息
// outb_p & inb_p是io.h中定义的端口输入输出宏
#define CMOS_READ(addr) ({ \
outb_p(0x80|addr,0x70); \ // 0x70-写地址端口号, 0x80|addr-要读取的CMOS内存地址
inb_p(0x71); \ // 0x81-读数据端口号
})

// 定义宏：将BCD码转换成二进制
// BCD码用半个字节(4-bit)表示已给10进制数,因此1字节表示2个10进制数
// val & 15(1111)表示取BCD的个位数, val>>4表示取十位数
// 两者加在一起就是1字节BCD码表示的二进制数
#define BCD_TO_BIN(val) ((val)=((val)&15) + ((val)>>4)*10)

// 取CMOS实时时钟信息作为开机时间，保存在全局变量startup_time中
static void time_init(void)
{
	struct tm time; // struct tm定义见time.h

	// CMOS访问很慢，为减小时间误差，在读取下面所有值后
	// 如果CMOS的秒值发生改变，就重新读取，保证误差在1s内
	do {
		time.tm_sec = CMOS_READ(0); // 当前时间秒值(BCD码),下同
		time.tm_min = CMOS_READ(2);
		time.tm_hour = CMOS_READ(4);
		time.tm_mday = CMOS_READ(7);
		time.tm_mon = CMOS_READ(8);
		time.tm_year = CMOS_READ(9);
	} while (time.tm_sec != CMOS_READ(0));
	// 将BCD码值转换为二进制
	BCD_TO_BIN(time.tm_sec);
	BCD_TO_BIN(time.tm_min);
	BCD_TO_BIN(time.tm_hour);
	BCD_TO_BIN(time.tm_mday);
	BCD_TO_BIN(time.tm_mon);
	BCD_TO_BIN(time.tm_year);
	time.tm_mon--; // tm_mon月份范围是0~11
	startup_time = kernel_mktime(&time); // 计算开机时间(自1970/1/1/0时以来的秒值)
}

static long memory_end = 0; // 物理内存容量(字节数)
static long buffer_memory_end = 0; // 高速缓冲区末端地址
static long main_memory_start = 0; // 主内存开始位置

struct drive_info { char dummy[32]; } drive_info; // 存放硬盘参数表信息

// 内核初始化主程序
void main(void)		/* This really IS void, no error here. */
{			/* The startup routine assumes (well, ...) this */
/*
 * Interrupts are still disabled. Do necessary setups, then
 * enable them
 */

	// 设置根设备号 高速缓存末端地址 内存数 主内存开始地址
 	ROOT_DEV = ORIG_ROOT_DEV;
 	drive_info = DRIVE_INFO; // 复制0x90080处的硬盘参数表
	memory_end = (1<<20) + (EXT_MEM_K<<10); // 内存大小(字节)=1MB + 扩展内存(k)*1024字节
	memory_end &= 0xfffff000; // 0x1000=4096，对其整除, 忽略不到1页的内存数
	if (memory_end > 16*1024*1024) // 如果内存超过16Mb，则按16Mb计
		memory_end = 16*1024*1024; 
	if (memory_end > 12*1024*1024) // 超过12Mb，缓冲区末端=4Mb 
		buffer_memory_end = 4*1024*1024;
	else if (memory_end > 6*1024*1024) // 超过6Mb，缓冲区末端=2Mb
		buffer_memory_end = 2*1024*1024;
	else
		buffer_memory_end = 1*1024*1024; // 否则，缓冲区末端=1Mn
	main_memory_start = buffer_memory_end; // 主内存起始位置=缓冲区末端
// 如果Makefile中定义了RAMDISK虚拟盘，则初始化虚拟盘，此时主内存将减少
#ifdef RAMDISK
	main_memory_start += rd_init(main_memory_start, RAMDISK*1024);
#endif
	mem_init(main_memory_start,memory_end); // 主内存初始化
	trap_init(); // trap初始化
	blk_dev_init(); // 块设备初始化
	chr_dev_init(); // 字符设备初始化
	tty_init(); // tty初始化
	time_init(); // 设置开机启动时间
	sched_init(); // 调度程序初始化
	buffer_init(buffer_memory_end); // 缓冲管理初始化
	hd_init(); // 硬盘初始化
	floppy_init(); // 软驱初始化
	sti(); // 初始化已结束，开启中断
// 利用中断返回指令，返回用户模式下执行(任务0)
	move_to_user_mode();
	if (!fork()) {		/* we count on this going ok */
		init(); // 在新建的子进程(任务1)中执行init()，其定义见后
	}
/*
 *   NOTE!!   For any other task 'pause()' would mean we have to get a
 * signal to awaken, but task0 is the sole exception (see 'schedule()')
 * as task 0 gets activated at every idle moment (when no other tasks
 * can run). For task0 'pause()' just means we go check if some other
 * task can run, and if not we return here.
 */
// pause()系统调用把任务0转换成可中断等待状态，再执行调度函数
	for(;;) pause();
}

// 产生格式化信息并输出到标准输出设备stdout(1)
// *fmt指定输出将采用的格式
static int printf(const char *fmt, ...)
{
	va_list args;
	int i;

	va_start(args, fmt);
	// 使用vsprintf()将格式化的字符串放入printbuf缓冲区
	// 再用write()将缓冲区内容输出到stdout(1)
	write(1,printbuf,i=vsprintf(printbuf, fmt, args));
	va_end(args);
	return i;
}

// 读取并执行/etc/rc文件时要用的命令行参数 & 环境参数
static char * argv_rc[] = { "/bin/sh", NULL };
static char * envp_rc[] = { "HOME=/", NULL };

// 运行登录shell时要用到的命令行参数 & 环境参数
static char * argv[] = { "-/bin/sh",NULL };
static char * envp[] = { "HOME=/usr/root", NULL };

// main()中已完成系统初始化,init()运行在任务0第一次创建的子进程(任务1)中
// 如果一个进程的父进程先终止了，它的父进程会被设为这里的init进程（任务1）
// 由init进程负责释放任务数据结构等资源
void init(void)
{
	int pid,i;

	setup((void *) &drive_info); // 读取硬盘参数并加载虚拟盘（如果有），安装根文件系统设备
	(void) open("/dev/tty0",O_RDWR,0); // 打开设备/dev/tty0，对应终端控制台(第一次打开文件，所以fd是0)
	(void) dup(0); // 复制句柄，产生句柄1号（stdout）
	(void) dup(0); // 复制句柄，产生句柄2号（stderr）
	// 打印缓冲区块数(每块1024字节)和总字节数
	printf("%d buffers = %d bytes buffer space\n\r",NR_BUFFERS,
		NR_BUFFERS*BLOCK_SIZE);
	// 打印主内存区空闲字节数
	printf("Free mem: %d bytes\n\r",memory_end-main_memory_start);
	// 创建子进程（任务2）
	if (!(pid=fork())) { // fork()=0，子进程
		close(0); // 关闭stdin
		if (open("/etc/rc",O_RDONLY,0)) // 以只读方式打开/etc/rc文件
			_exit(1);
		execve("/bin/sh",argv_rc,envp_rc); // 执行/bin/sh（shell程序）
		_exit(2);
	}
	if (pid>0) // 父进程
		// wait()等待子进程停止或终止，返回值应是子进程的进程号
		// &i存放返回状态信息
		while (pid != wait(&i))
			/* nothing */;
	// 执行到这里说明上面的子进程停止或终止了，下面循环再创建一个子进程
	while (1) {
		if ((pid=fork())<0) { // 创建失败
			printf("Fork failed in init\r\n");
			continue;
		}
		if (!pid) { // 子进程
			close(0);close(1);close(2); // 关闭以前遗留的句柄stdin, stdout, stderr
			setsid(); // 创建新会话
			(void) open("/dev/tty0",O_RDWR,0); // 重新打开/dev/tty0作为stdin
			(void) dup(0); // 复制成stdout
			(void) dup(0); // 复制成stderr
			_exit(execve("/bin/sh",argv,envp)); // 执行shell，但参数改了
		}
		while (1)
			if (pid == wait(&i))
				break;
		printf("\n\rchild %d died with code %04x\n\r",pid,i);
		sync();
	}
	_exit(0);	/* NOTE! _exit, not exit() */
}
