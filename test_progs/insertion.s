/*
   GROUP 17
	TEST PROGRAM: insertion sort

	long a[] = { 3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5, 8, 9, 7, 9, 3 };

  int i,j,temp;
  for(i=1;i<16;++i) {
    temp = a[i];
    j = i;
    while(1) {
      if(a[j-1] > temp)
        a[j] = a[j-1];
      else
        break; 
      --j;
      if(j == 0) 
        break;      
    }
    a[j] = temp;
  }  
  
  modified from sort.s
*/

 br	start                                                       #04
  .align 3
  .quad	3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5, 8, 9, 7, 9, 3 
  .align 3
start:	                                
  lda $r5,1   # i=1                                             #94

  lda $r9,16 #index to a[1]                                     #90

iloop:
  ldq $r3, 0($r9) #temp = a[i]                                  #94
  mov $r5,$r6     #j = i                                        #98
  mov $r9,$r19     #index j                                     #9c  
  subq $r19,8,$r18 #index j-1                                   #a0
jloop:
  ldq $r14, 0($r18) #r14 = a[j-1]                               #a4
  ldq $r15, 0($r19) #r15 = a[j]                                 #a8

  cmpult $r14,$r3, $r11                                         #ac
  bne $r11,ifinish                                              #ac
  
  stq $r14, 0($r19) #a[j] = temp                                #b0
  
  subq $r18,8,$r18  #index to a[j-1]
  subq $r19,8,$r19  #index to a[j]
  
  subq $r6,1,$r6  #j--
  beq $r6, ifinish 
  br jloop
  
ifinish:
  stq $r3, 0($r19) #a[j] = temp
  addq $r9,8,$r9
  addq $r5,1,$r5  #increment and check i loop
  
  cmpult $r5,16, $r10
  bne $r10, iloop

  call_pal 0x555 #finish

  
