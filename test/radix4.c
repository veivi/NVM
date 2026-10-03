void fft_radix4(complex_t A[])
{
  int s = 0, k = 0, j = 0, span = 0, quarter = 0, index_mult = 0;
  complex_t plus_i = COMPLEX_FROM_FLOAT(0.0f, 1.0f), minus_i = COMPLEX_FROM_FLOAT(0.0f, -1.0f);
  complex_t a0[V], a1[V], a2[V], a3[V], w1[V], w2[V], w3[V];
  complex_t t1[V], t2[V], t3[V], s0[V], s1[V], s2[V], s3[V];
  complex_t y0[V], y1[V], y2[V], y3[V];
  complex_t r3n[V], r3p[V];

  // for stage = 1 .. log4(N):
  
  for(s = 1; s <= LOG4LEN; s++) {
    span = 1<<(2 * s);  // 4^s
    quarter = span / 4;

    index_mult = FFT_LEN / span;
    
    // span    = 4^stage
    // quarter = span / 4

    // if quarter >= V:
    
    if(quarter >= V) {
      // late stage: contiguous within a block, twiddle vectors

      // for k = 0, span, 2*span, ... N-span:

      for(k = 0; k < FFT_LEN; k += span) {
	
	// for j = 0, V, 2V, ... quarter-V:

	for(j = 0; j < quarter; j += V) {
	  
	  printf("---\ns = %d k = %d j = %d\n---\n", s, k, j);
	
	  /*
                VLD   a0, [a + k+j]
                VLD   a1, [a + k+j+quarter]
                VLD   a2, [a + k+j+2*quarter]
                VLD   a3, [a + k+j+3*quarter]
                VLD   w1, [twid1 + j]
                VLD   w2, [twid2 + j]
                VLD   w3, [twid3 + j]
	  */

	  complex_vector_read(a0, A, k + j, 1, 0x130);
	  complex_vector_read(a1, A, k + j + quarter, 1, 0x130);
	  complex_vector_read(a2, A, k + j + 2*quarter, 1, 0x130);
	  complex_vector_read(a3, A, k + j + 3*quarter, 1, 0x130);
	  
	  complex_vector_read(w1, w, 0, j * index_mult, 0x10000);
	  complex_vector_read(w2, w, 0, j * 2*index_mult, 0x10000);
	  complex_vector_read(w3, w, 0, j * 3*index_mult, 0x10000);

	  /*
                t0 = a0
                VCMUL t1, w1, a1
                VCMUL t2, w2, a2
                VCMUL t3, w3, a3
	  */

	  complex_vector_mul(t1, w1, a1);
	  complex_vector_mul(t2, w2, a2);
	  complex_vector_mul(t3, w3, a3);

	  /*
                VCADD s0, t0, t2    VCSUB s1, t0, t2
                VCADD s2, t1, t3    VCSUB s3, t1, t3
	  */

	  complex_vector_add(s0, a0, t2);
	  complex_vector_sub(s1, a0, t2);
	  complex_vector_add(s2, t1, t3);
	  complex_vector_sub(s3, t1, t3);

	  /*
                VCADD y0, s0, s2
                VCSUB y2, s0, s2
                VROTNJ r3n, s3      VROTJ r3p, s3
                VCADD y1, s1, r3n
                VCADD y3, s1, r3p
	  */

	  complex_vector_add(y0, s0, s2);
	  complex_vector_sub(y2, s0, s2);
	  complex_vector_mul_bc(r3n, s3, &minus_i);
	  complex_vector_mul_bc(r3p, s3, &plus_i);
	  complex_vector_add(y1, s1, r3n);
	  complex_vector_add(y3, s1, r3p);
	  
	  /*
                VST [a + k+j],           y0
                VST [a + k+j+quarter],   y1
                VST [a + k+j+2*quarter], y2
                VST [a + k+j+3*quarter], y3
	  */

	  complex_vector_write(y0, A, k + j, 1, 0x130);
	  complex_vector_write(y1, A, k + j + quarter, 1, 0x130);
	  complex_vector_write(y2, A, k + j + 2*quarter, 1, 0x130);
	  complex_vector_write(y3, A, k + j + 3*quarter, 1, 0x130);

	}
      }
    } else {
	  
      // early stage: small blocks, broadcast twiddle, strided across blocks
      // for j = 0 .. quarter-1:

      for(j = 0; j < quarter; j++) {
	    
	printf("---\ns = %d j = %d\n---\n", s, j);
	
	// w1j, w2j, w3j = twid1[j], twid2[j], twid3[j]   // scalars

	complex_t w1j = w[j * index_mult], w2j = w[j * 2*index_mult], w3j = w[j * 3*index_mult];

	/*
	  VLD    a0, [a + j],            stride=span
	  VLD    a1, [a + j+quarter],    stride=span
	  VLD    a2, [a + j+2*quarter],  stride=span
	  VLD    a3, [a + j+3*quarter],  stride=span
	*/

	complex_vector_read(a0, A, j, span, 0x130);
	complex_vector_read(a1, A, j + quarter, span, 0x130);
	complex_vector_read(a2, A, j + 2*quarter, span, 0x130);
	complex_vector_read(a3, A, j + 3*quarter, span, 0x130);

	/*
            t0 = a0
            VBCMUL t1, w1j, a1
            VBCMUL t2, w2j, a2
            VBCMUL t3, w3j, a3
	*/
	
	complex_vector_mul_bc(t1, a1, &w1j);
	complex_vector_mul_bc(t2, a2, &w2j);
	complex_vector_mul_bc(t3, a3, &w3j);

	/*
            VCADD s0, t0, t2    VCSUB s1, t0, t2
            VCADD s2, t1, t3    VCSUB s3, t1, t3
	*/

	complex_vector_add(s0, a0, t2);
	complex_vector_sub(s1, a0, t2);
	complex_vector_add(s2, t1, t3);
	complex_vector_sub(s3, t1, t3);

	/*
            VCADD y0, s0, s2
            VCSUB y2, s0, s2
            VROTNJ r3n, s3      VROTJ r3p, s3
            VCADD y1, s1, r3n
            VCADD y3, s1, r3p
	*/

	complex_vector_add(y0, s0, s2);
	complex_vector_sub(y2, s0, s2);
	complex_vector_mul_bc(r3n, s3, &minus_i);
	complex_vector_mul_bc(r3p, s3, &plus_i);
	complex_vector_add(y1, s1, r3n);
	complex_vector_add(y3, s1, r3p);

	/*
            VST [a + j],            y0, stride=span
            VST [a + j+quarter],    y1, stride=span
            VST [a + j+2*quarter],  y2, stride=span
            VST [a + j+3*quarter],  y3, stride=span
	*/

	complex_vector_write(y0, A, j, span, 0x130);
	complex_vector_write(y1, A, j + quarter, span, 0x130);
	complex_vector_write(y2, A, j + 2*quarter, span, 0x130);
	complex_vector_write(y3, A, j + 3*quarter, span, 0x130);
      }
    }
    
    //STORE_FENCE   // required once per radix-4 stage, same cross-stage RAW hazard as before
  }
}
