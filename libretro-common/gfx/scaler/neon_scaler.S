/* Copyright  (C) 2010-2015 The RetroArch team
 * Copyright  (C) 2016 Fox Cunning
 *
 * ---------------------------------------------------------------------------------------
 * The following license statement only applies to this file (scaler_int.c).
 * ---------------------------------------------------------------------------------------
 *
 * Permission is hereby granted, free of charge,
 * to any person obtaining a copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation the rights to
 * use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software,
 * and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
 * INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */
	.syntax unified
	.arch armv7-a
	.eabi_attribute 27, 3
	.eabi_attribute 28, 1
	.fpu neon
	.eabi_attribute 23, 1
	.eabi_attribute 24, 1
	.eabi_attribute 25, 1
	.eabi_attribute 26, 2
	.eabi_attribute 30, 2
	.eabi_attribute 34, 1
	.eabi_attribute 18, 4

.macro	__copy_1px out, in, x, step
	lsr	r12, \x, #16
	ldr	r12, [\out, r12, lsl #2]
	str	r12, [\in], #4
	add	\x, \x, \step			@ x += x_step
.endm

	.arm
	.text
	.align	4
	.global	scaler_argb8888_point_special
	.type	scaler_argb8888_point_special, %function
scaler_argb8888_point_special:
	@ args = 20, pretend = 0, frame = 0
	@ frame_needed = 0, uses_anonymous_args = 0
	@ link register save eliminated.
	push	{r4-r12}		@ 9 regs pushed: sp += 36
	
	ldr	r4, [sp, #(0+36)]	@ r4 = out_height
	ldr	r5, [sp, #(4+36)]	@ r5 = in_width
	ldr	r6, [sp, #(8+36)]	@ r6 = in_height
	ldr	r7, [sp, #(12+36)]	@ r7 = out_stride
	ldr	r8, [sp, #(16+36)]	@ r8 = in_stride

	@ d0[0] = (float)(in_width << 16), d0[1] = (float)(in_height << 16)
	vdup.32	d0, r5
	vmov.32	d0[1], r6
	vshl.i32	d0, d0, #16
	vcvt.f32.u32	d0, d0
	
	@ d1[0] = (float)out_width, d1[1] = (float)out_height
	vdup.32	d1, r3
	vmov.32	d1[1], r4
	vcvt.f32.u32	d1, d1
	
	@ d0 = (uint)(d0 * (1 / d1))
	vrecpe.f32	d1, d1
	
	vmul.f32	d0, d0, d1
	vcvt.u32.f32	d0, d0
	
	vmov.u32	r5, d0[0]	@ r5 = x_step = d0[0]
	vmov.u32	r10, d0[1]	@ r10 = y_step = d0[1]
	
	mov	r6, #0				@ r6 = y_pos = 0
	
.LoopH:
	mov	r9, #0				@ x = 0 (assume x_pos = 0)
	lsr	r0, r6, #16			@ r0 = inp = y_pos >> 16
	mul	r0, r0, r8			@ inp *= in_stride
	add	r0, r0, r2			@ inp += input_
	
	mov	r11, r3				@ w = out_width
.LoopW:
	@ Load value from inp[x >> 16] in a temp register (r12)
	@ Since it's a word (4 bytes) we need to multiply x * 4, which is the same as x << 2, so (x >> 16) << 2 or (x >> 14) & 0xfffffffc
	lsr	r12, r9, #16
	ldr	r12, [r0, r12, lsl #2]

	@ Store the value from temp register (r12) to the address in r1, then increase r1
	str	r12, [r1], #4
	
	add	r9, r9, r5			@ x += x_step


	@ ...do it 79 more times
	.rept 79
	__copy_1px r0, r1, r9, r5
	.endr
	
	subs	r11, r11, #80	@ w -= 80
	bne	.LoopW				@ LoopW while (w != 0)
	
	add	r6, r6, r10			@ y_pos += y_step
	
	subs	r4, r4, #1		@ --out_height

	bne	.LoopH			@ LoopH while (out_height != 0)
	
	pop	{r4-r12}
	bx	lr
	.size	scaler_argb8888_point_special, .-scaler_argb8888_point_special


	.text
	.arm
	.align 4
	.global neon_256x224_to_720x480
	.type	neon_256x224_to_720x480, %function
neon_256x224_to_720x480:	@ (void* unused, u32* dst, u32* src)
	stmfd	sp!,{r4,lr}
	
	@ To centre the image, move the starting output pointer to (720/2-512/2), (480/2-448/2) => 104, 16
	add r1, r1, #(720*4*16)	@ Go down 16 rows
	add	r1, r1,	#(4*104)	@ Advance 104 pixels
	
	mov	r4, #224	@ r4 = y counter
.LoopH_1:

	mov	r3, #256	@ r3 = x counter
.LoopW_1:
	vld4.32	{d0[], d1[], d2[], d3[]}, [r2:64]!		@ Read 4 pixels, duplicating them
	vld4.32	{d4[], d5[], d6[], d7[]}, [r2:64]!		@ Read 4 more pixels, duplicating them

	mov	r0, r1		@ r0 = base output address for the current row
	
	vst1.32	{d0, d1, d2, d3}, [r0:128]!				@ Store the duplicated pixels
	vst1.32 {d4, d5, d6, d7}, [r0:128]
	
	add	r0, r1, #720*4							@ Move down one row
	vst1.32	{d0, d1, d2, d3}, [r0:128]!			@ Duplicate row
	vst1.32	{d4, d5, d6, d7}, [r0:128]
	add r1, r1, #16*4							@ Output x += 16 pixels

	subs	r3, r3, #8							@ x -= 8
	bne	.LoopW_1								@ LoopW while x != 0

	add	r1, r1, #((720-512))*4+(720*4)			@ Move dst pointer to next row

	subs	r4, r4, #1							@ y--
	bne	.LoopH_1								@ LoopH while y != 0
	
	ldmfd	sp!,{r4, pc}
	
	.size	neon_256x224_to_720x480, .-neon_256x224_to_720x480



	.text
	.arm
	.align 4
	.global neon_512x224_to_720x480
	.type	neon_512x224_to_720x480, %function
neon_512x224_to_720x480:	@ (void* unused, u32* dst, u32* src)
	stmfd	sp!,{r4,lr}
	
	@ To centre the image, move the starting output pointer to (720/2-512/2), (480/2-448/2) => 104, 16
	add r1, r1, #(720*4*16)	@ Go down 16 rows
	add	r1, r1,	#(4*104)	@ Advance 104 pixels
	
	mov	r4, #224	@ r4 = y counter
.LoopH_2:
	
	mov	r3, #512	@ r3 = x counter
.LoopW_2:
	vld1.32	{d0, d1, d2, d3}, [r2:64]!		@ Read 8 pixels
	vld1.32	{d4, d5, d6, d7}, [r2:64]!		@ Read 8 more pixels

	mov	r0, r1
	
	vst1.32	{d0, d1, d2, d3}, [r0:128]!		@ Store the pixels
	vst1.32 {d4, d5, d6, d7}, [r0:128]
	
	add	r0, r1, #720*4					@ Move down one row
	vst1.32	{d0, d1, d2, d3}, [r0:128]!		@ Duplicate row
	vst1.32	{d4, d5, d6, d7}, [r0:128]

	add r1, r1, #16*4					@ Output x += 16 pixels

	subs	r3, r3, #16					@ x -= 16
	bne	.LoopW_2						@ LoopW while x != 0

	add	r1, r1, #((720-512)*4)+(720*4)	@ Move dst pointer to next row

	subs	r4, r4, #1					@ y--
	bne	.LoopH_2						@ LoopH while y != 0
	
	ldmfd	sp!,{r4, pc}
	
	.size	neon_512x224_to_720x480, .-neon_512x224_to_720x480
	
	
	

	.ident	"GCC: (Debian 4.9.2-10) 4.9.2"
	.section	.note.GNU-stack,"",%progbits
