
.data					# section declaration

        # Useful offset constants for accessing members of a 
        # struct mp1_blink_struct structure
        LOCATION   = 0    
        ON_CHAR    = 2
        OFF_CHAR   = 3 
        ON_LENGTH  = 4
        OFF_LENGTH = 6
        COUNTDOWN  = 8
        STATUS     = 10
        NEXT       = 12

        STRUCT_SIZE = 16

# Pointer to head of list (initialized to NULL)
mp1_list_head:
        .long   0

.text					# section declaration

# Export the function symbol names

.global mp1_rtc_tasklet
.global mp1_ioctl

# void mp1_poke(void);
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX
mp1_poke:
        
	movl    vmem_base_addr(,1),%edx
	movb    %cl,(%edx,%eax,1)
	ret



# void mp1 rtc tasklet (unsigned long);
#
# This function updates the state of the game by
# walking down the list and examining each struct
# Different character will be put on according to the struct's status
# mp1_poke is also called to put characters out to video memory
# It does not have a return value
mp1_rtc_tasklet:
	pushl	%ebp			#create the stack frame
	movl	%esp, %ebp
	pushl	%ebx
	pushl	%esi
	pushl	%edi
	#parameter (unsigned long) is unused here
	movl 	mp1_list_head, %ebx		#set ebx to the first struct
	
loop_start:
	cmpl	$0, %ebx				#check ebx value
	je		tasklet_end				#resolves the line77(testcases.c) bug
	decw	COUNTDOWN(%ebx)
	cmpw	$0, COUNTDOWN(%ebx)
	jne		loop_end

check_status:
	cmpw	$0, STATUS(%ebx)
	ja		display_on
	je		display_off

display_on:
	movb	OFF_CHAR(%ebx), %cl			#cl  - The ASCII code of the char you wish to write
	xorl	%eax, %eax					#reset eax to 0 before using ax to prevent segfault
	movw	LOCATION(%ebx), %ax			#eax - Offset from the start of video memory that you wish to write to
	addw	%ax, %ax
	call	mp1_poke
	xorl	%edx, %edx					#reset edx to 0 before using dx to prevent segfault			
	movw	OFF_LENGTH(%ebx), %dx		#opposite length field to countdown.
	movw	%dx, COUNTDOWN(%ebx)
	movw	$0, STATUS(%ebx)			#interchange the status between on/off
	jmp		loop_end
	
display_off:
	movb	ON_CHAR(%ebx), %cl			#cl  - The ASCII code of the char you wish to write
	xorl	%eax, %eax					#reset eax to 0 before using ax to prevent segfault
	movw	LOCATION(%ebx), %ax			#eax - Offset from the start of video memory that you wish to write to
	addw	%ax, %ax
	call	mp1_poke
	xorl	%edx, %edx					#reset edx to 0 before using dx to prevent segfault
	movw	ON_LENGTH(%ebx), %dx		#opposite length field to countdown.
	movw	%dx, COUNTDOWN(%ebx)
	movw	$1, STATUS(%ebx)			#interchange the status between on/off
	
loop_end:
	cmpl	$0, NEXT(%ebx)			#check if reaches end of list
	je		tasklet_end
	movl	NEXT(%ebx), %ebx		#points ebx to the next struct
	jmp		loop_start
	
tasklet_end:
	popl	%edi			#tear down stack frame
	popl	%esi		
	popl	%ebx
	leave
	ret
	


# int mp1_ioctl (unsigned long arg, unsigned long cmd);
#
# This function serves as the dispatcher function that chooses
# the subfunction to execute corresponding to the parameter value
# using a jumptable
# cmd = 0: jump to mp1_ioctl_add
# cmd = 1: jump to mp1_ioctl_remove
# cmd = 2: jump to mp1_ioctl_find
# cmd = 3: jump to mp1_ioctl_sync
# This function returns -1 if the cmd value is invalid
mp1_ioctl:
	#Dispatcher does not modify stack. No need to setup stack frame
	#use esp instead of ebp here
	movl	8(%esp), %ecx	#cmd, the index for the jump table
	cmpl	$3, %ecx		#check cmd is in range
	ja		invalid_cmd
	cmpl	$0, %ecx
	jb		invalid_cmd
	jmp		*jumptable(, %ecx, 4)
invalid_cmd:
	movl	$-1, %eax		#return -1
	leave
	ret
jumptable:
	.long mp1_ioctl_add, mp1_ioctl_remove, mp1_ioctl_find, mp1_ioctl_sync



# int mp1 ioctl add(unsigned long arg);
#
# This function takes as its argument a user-level pointer to a mp1 blink struct structure.
# With mp1_malloc and mp1_copy_from_user, it is able to
# dynamically allocate memory for the new struct and
# copy data from the struct that arg points to.
# This function returns 0 if a successful add was performed
# and returns 1 if there is any error
mp1_ioctl_add:
	pushl	%ebp			#create the stack frame
	movl	%esp, %ebp
	pushl	%ebx
	pushl	%esi
	pushl	%edi
	
	movl	8(%ebp), %esi	#store arg into esi
	cmpl	$0, %esi		#check if arg is valid
	je		fail_add
	
	pushl 	$STRUCT_SIZE	#push the argument
	call	mp1_malloc
	addl	$4, %esp		#pop the argument
	movl	%eax, %ebx		#ebx now have the addr of the new struct
	cmpl	$0, %eax		#check return value of malloc
	je 		fail_add
	
	pushl	$STRUCT_SIZE	#n
	pushl	%esi			#pointer from, aka arg
	pushl	%ebx			#pointer to
	call 	mp1_copy_from_user	#void *to, const void *from, unsigned long n
	addl	$12, %esp		#pop the argument
	cmpl	$0, %eax		#check return value of mp1_copy_from_user
	jne		add_free
	
	movw	ON_LENGTH(%ebx), %ax	#move on_length to countdown
	movw	%ax, COUNTDOWN(%ebx)
	movw 	$1, STATUS(%ebx)
	movl	mp1_list_head, %edi		#connect struct to the list
	movl	%edi, NEXT(%ebx)
	movl	%ebx, mp1_list_head		#update list_head 
	
	cmpw	$0, LOCATION(%ebx)		#check location is in range
	jb		add_free
	cmpw	$80*25-1, LOCATION(%ebx)
	ja		add_free
	

	movb	ON_CHAR(%ebx), %cl			#cl  - The ASCII code of the char you wish to write
	movw	LOCATION(%ebx), %ax			#eax - Offset from the start of video memory that you wish to write to
	addw	%ax, %ax
	call	mp1_poke
	
successful_add:
	movl	$0, %eax		#return 0 if add is successful
	popl	%edi			#tear down stack frame
	popl	%esi		
	popl	%ebx
	leave
	ret

add_free:
	push	%ebx
	call 	mp1_free
	addl	$4, %esp
	jmp 	fail_add
	
fail_add:
	movl	$-1, %eax		#return -1 if add fails
	popl	%edi			#tear down stack frame
	popl	%esi		
	popl	%ebx
	leave
	ret



# int mp1 ioctl remove(unsigned long arg)
#
# The remove ioctl takes an integer location as its parameter. 
# It traverses the list, looking for an element whose location field matches the argument.
# It removes the element from the list, free its memory, and return 0.
# If the function does not find the element, it returns -1.
mp1_ioctl_remove:
	pushl	%ebp						#create the stack frame
	movl	%esp, %ebp
	pushl	%ebx
	pushl	%esi
	pushl	%edi
	movl	8(%ebp), %esi				#store arg into esi(location)
	movl	8(%ebp), %edx				#move correct value to dx
	call	loop_helper					#check if we can find the struct first
	cmpl	$0, %eax
	je		remove_fail
	movl	%eax, %edi					#edi now has the struct we want to remove

	#perform linked list remove
	cmpl	mp1_list_head, %edi			#check if head is the one to remove
	jne		remove_loop					#the list_head is not the one to remove
	
	movl	NEXT(%edi), %ebx			#remove head
	movl	%ebx, mp1_list_head			#head = head.next
	push	%edi
	call 	mp1_free
	addl	$4, %esp
	movl	$0, %eax					#return 0
	jmp		remove_end
	
remove_loop:
	movl	mp1_list_head, %ebx			#ebx holds the current object we are visiting
remove_loop_actual_start:				#resolves the bug that program does not stop automatically
	#find the struct whose next == remove_addr
	cmpl	NEXT(%ebx), %edi
	je		remove_found
	movl	NEXT(%ebx), %ebx
	jmp		remove_loop_actual_start
remove_found:
	movl	NEXT(%edi), %ecx			#NEXT(%ebx) = NEXT(%edi)
	movl	%ecx, NEXT(%ebx)
	push	%edi
	call 	mp1_free
	addl	$4, %esp
	movl	$0, %eax					#return 0
	jmp		remove_end
remove_fail:
	movl	$-1, %eax
remove_end:
	popl	%edi						#tear down stack frame
	popl	%esi		
	popl	%ebx
	leave
	ret

    

# int mp1 ioctl find(unsigned long arg)
#
# This function takes a pointer to a mp1 blink struct.
# It searches the list for an element that matches the location 
# Then copy the entire element to the user-level structure 
# pointed to by the parameter that was passed in
# returns -1 if no matching location in the list, otherwise returns 0.   
mp1_ioctl_find:
	pushl	%ebp			#create the stack frame
	movl	%esp, %ebp
	pushl	%ebx
	pushl	%esi
	pushl	%edi
	
	movl	8(%ebp), %esi				#store arg into esi
	movw	LOCATION(%esi), %dx			#get arg's location and store it in dx
	
	#search for the struct with same location
	call loop_helper
	cmpl $0, %eax			#check return value of helper function
	je	find_fail
	movl %eax, %ebx
	
find_success:
	pushl	$STRUCT_SIZE	#n
	pushl	%ebx			#pointer from, aka arg
	pushl	%esi			#pointer to
	call 	mp1_copy_from_user	#void *to, const void *from, unsigned long n
	addl	$12, %esp		#pop the argument
	cmpl	$0, %eax		#check return value of mp1_copy_from_user
	jne		find_fail
	movl	$0, %eax
	jmp find_end
	
find_fail:
	movl	$-1, %eax
find_end:
	popl	%edi			#tear down stack frame
	popl	%esi		
	popl	%ebx
	leave
	ret



# int mp1 ioctl sync(unsigned long arg)
#
# The argument is two two-byte unsigned short integers
# The first integer is stored in the upper 16 bits of arg, 
# and the second integer is stored in the lower 16 bits.
# It searches from the list for a struct with same location 
# Then copy the timing information from the first element to the second element.
# returns 0 on success, -1 on failure  
mp1_ioctl_sync:
	pushl	%ebp			#create the stack frame
	movl	%esp, %ebp
	pushl	%ebx
	pushl	%esi
	pushl	%edi
	
	movl	8(%ebp), %ecx			#store arg into ecx
	movw	%cx, %dx				#dx now has the second int
	call 	loop_helper
	cmpl	$0, %eax				#check return value of helper function
	je		sync_fail
	movl	%eax, %edi				#edi now has the second object we found
	shrl	$16, %ecx				#shift right 16 bits
	movw	%cx, %dx				#dx now has the first int
	call 	loop_helper
	cmpl	$0, %eax				#check return value of helper function
	je		sync_fail
	movl	%eax, %esi				#esi now has the first object we found
	
	#now we have esi - first object, edi - second object
	#copy on length, off length, countdown, and status from first(esi) to second(edi)
	#bx is used as the temp reg for all the copying codes below
	movw 	ON_LENGTH(%esi), %bx
    movw 	%bx, ON_LENGTH(%edi)
    movw 	OFF_LENGTH(%esi), %bx
    movw 	%bx, OFF_LENGTH(%edi)
    movw 	COUNTDOWN(%esi), %bx
    movw 	%bx, COUNTDOWN(%edi)
    movw 	STATUS(%esi), %bx
    movw 	%bx, STATUS(%edi)
	
	cmpw	$0, STATUS(%edi)
	je		sync_off

sync_on:
	movb	ON_CHAR(%edi), %cl			#cl  - The ASCII code of the char you wish to write
	xorl	%eax, %eax
	movw	LOCATION(%edi), %ax			#eax - Offset from the start of video memory that you wish to write to
	addw	%ax, %ax
	call	mp1_poke
	jmp		sync_success
sync_off:
	movb	OFF_CHAR(%edi), %cl			#cl  - The ASCII code of the char you wish to write
	xorl	%eax, %eax
	movw	LOCATION(%edi), %ax			#eax - Offset from the start of video memory that you wish to write to
	addw	%ax, %ax
	call	mp1_poke
	jmp		sync_success
	
sync_success:
	movl	$0, %eax
	jmp		sync_end
sync_fail:
	movl	$-1, %eax
sync_end:
	popl	%edi			#tear down stack frame
	popl	%esi		
	popl	%ebx
	leave
	ret



# void loop_helper(void);
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %dx -- the location we are searching
# This helper function searches in the list
# for a struct that has the same location
# returns the pointer to the struct on success
# returns 0 on failure
loop_helper:		#used in find & sync
	#traverse the list and find the struct with same location
	movl	mp1_list_head, %ebx			#ebx holds the current object we are visiting
	cmpl	$0, %ebx					#check if the list is empty
	je		helper_fail
helper_start:
	cmpw	LOCATION(%ebx), %dx			#check if it has same location value
	je		helper_success
	cmpl	$0, NEXT(%ebx)				#check if reaches end of list
	je		helper_fail
	movl	NEXT(%ebx), %ebx
	jmp		helper_start
helper_success:
	movl	%ebx, %eax					#return the address of the object we found
	ret
helper_fail:
	movl	$0, %eax
	ret

.end
	
	
	
	