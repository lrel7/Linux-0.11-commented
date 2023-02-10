/*
 *  linux/kernel/asm.s
 *
 *  (C) 1991  Linus Torvalds
 */

/*
 * asm.s contains the low-level code for most hardware faults.
 * page_exception is handled by the mm, so that isn't here. This
 * file also handles (hopefully) fpu-exceptions due to TS-bit, as
 * the fpu must be properly saved/resored. This hasn't been tested.
 */

# 全局函数名的声明
.globl divide_error,debug,nmi,int3,overflow,bounds,invalid_op
.globl double_fault,coprocessor_segment_overrun
.globl invalid_TSS,segment_not_present,stack_segment
.globl general_protection,coprocessor_error,irq13,reserved

# 处理无出错号的情况
# 除数是0产生的异常
divide_error:
	pushl $do_divide_error # do_divide_error函数的地址入栈
no_error_code:
	xchgl %eax,(%esp) # do_divide_error的地址存放在eax寄存器，xchgl指令将其与esp寄存器交换
	pushl %ebx # 将参数入栈
	pushl %ecx
	pushl %edx
	pushl %edi
	pushl %esi
	pushl %ebp
	push %ds
	push %es
	push %fs
	pushl $0		# 将0作为出错码入栈
	lea 44(%esp),%edx # 将原调用返回地址存放在edx寄存器（前面共将44 bytes的数据入栈，因此原调用返回地址在sp+44处）
	pushl %edx # 将原调用返回地址重新入栈
	movl $0x10,%edx
	mov %dx,%ds
	mov %dx,%es
	mov %dx,%fs
	call *%eax # 调用eax指定地址处的函数（调用引用本次异常的C处理函数，如do_divide_error()等）
	addl $8,%esp # sp+8，相当于两次pop操作，丢弃最后两个入栈的原调用返回地址和出错码0，让栈指针指向寄存器fs入栈处
	pop %fs # 将fs，es，ds分别从栈中弹出到对应的寄存器
	pop %es
	pop %ds
	popl %ebp # 将各参数弹出到对应的寄存器
	popl %esi
	popl %edi
	popl %edx
	popl %ecx
	popl %ebx
	popl %eax
	iret

# debug调试中断入口处
# 类型：fault/trap
# 错误号：无
debug:
	pushl $do_int3		# _do_debug C函数指针入栈，以下同
	jmp no_error_code # 跳转到上面的no_error_code入口

# 非屏蔽中断(NMI)调用入口处
# 类型：trap
# 错误号：无
nmi:
	pushl $do_nmi
	jmp no_error_code

# 断点指令中断入口处
# 类型：trap
# 错误号：无
int3:
	pushl $do_int3
	jmp no_error_code

# 溢出出错处理中断入口处
# 类型：trap
# 错误号：无
overflow:
	pushl $do_overflow
	jmp no_error_code

# 边界检查出错中断入口处
# 类型：fault
# 错误号：无
bounds:
	pushl $do_bounds
	jmp no_error_code

# 无效操作指令出错中断入口处
# 类型：fault
# 错误号：无
invalid_op:
	pushl $do_invalid_op
	jmp no_error_code

# 协处理器段超出出错中断入口处
# 类型：放弃
# 错误号：无
coprocessor_segment_overrun:
	pushl $do_coprocessor_segment_overrun
	jmp no_error_code

# 其他Intel保留中断的入口处
reserved:
	pushl $do_reserved
	jmp no_error_code

# 协处理器执行完一个操作时，就会发出IRQ13中断信号，以通知CPU操作完成
irq13:
	pushl %eax
	xorb %al,%al
	outb %al,$0xF0
	movb $0x20,%al
	outb %al,$0x20
	jmp 1f
1:	jmp 1f
1:	outb %al,$0xA0
	popl %eax
	jmp coprocessor_error

# 双出错故障(通常CPU调用前一个异常的处理程序而又检测到一个新的异常时，这两个异常会被串行地
# 进行处理；较少情况下CPU不能进行这样的串行处理，便引发此中断)
# 类型：放弃
# 有错误码
double_fault:
	pushl $do_double_fault
error_code:
	xchgl %eax,4(%esp)		# error code <-> %eax(error code的值作为第一个参数保存在sp+4的位置，将sp+4与eax寄存器交换)
	xchgl %ebx,(%esp)		# &function <-> %ebx
	pushl %ecx
	pushl %edx
	pushl %edi
	pushl %esi
	pushl %ebp
	push %ds
	push %es
	push %fs
	pushl %eax			# error code入栈
	lea 44(%esp),%eax		# offset(程序返回地址处的堆栈指针)
	pushl %eax
	movl $0x10,%eax # 设置内核数据段选择符
	mov %ax,%ds
	mov %ax,%es
	mov %ax,%fs
	call *%ebx # 间接调用相应的C函数，其参数均已入栈
	addl $8,%esp
	pop %fs
	pop %es
	pop %ds
	popl %ebp
	popl %esi
	popl %edi
	popl %edx
	popl %ecx
	popl %ebx
	popl %eax
	iret

# 无效的任务状态段
# 类型：fault
# 有错误码
invalid_TSS:
	pushl $do_invalid_TSS
	jmp error_code

# 段不存在
# 类型：fault
# 有错误码
segment_not_present:
	pushl $do_segment_not_present
	jmp error_code

# 堆栈段错误(指令操作试图超出堆栈段范围)
# 类型：fault
# 有错误码
stack_segment:
	pushl $do_stack_segment
	jmp error_code

# 一般性保护出错
# 类型：fault
# 有错误码
general_protection:
	pushl $do_general_protection
	jmp error_code

