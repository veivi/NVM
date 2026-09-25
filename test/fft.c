#include <stdio.h>
#include <math.h>

#define  LOG2LEN  10
#define  pi  ((float) M_PI)

typedef struct complex {
  float real, imag;
} complex_t;

#define COMPLEX(r, i) (complex_t) { .real = r, .imag = i }
#define COMPLEX_ADD(a, b) (complex_t) { a.real + b.real, a.imag + b.imag }
#define COMPLEX_MUL(a, b) (complex_t) { a.real*b.real-a.imag*b.imag, a.real*b.imag+a.imag*b.real }
#define COMPLEX_ABS(a) sqrtf(a.real*a.real + a.imag*a.imag)

complex_t fft_data[1<<LOG2LEN];
complex_t w[1<<LOG2LEN];

int bit_reverse(int I)
{
  int j = 0, result = 0;
  for(j = 0; j < LOG2LEN; j++) {
    result = (result<<1) | (I & 1);
    I >>= 1;
  }
  return result;
}

void bit_reversal_permutation(complex_t *data)
{
  int i = 0;
  
  for(i = 0; i < 1<<LOG2LEN; i++) {
    int rev = bit_reverse(i);

    if(i < rev) {
      complex_t temp = data[i];
      data[i] = data[rev];
      data[rev] = temp;
    }
  }
}

void fft(complex_t *A)
{
  int s = 0, k = 0, m = 0, half_m = 0, j = 0;
  complex_t omega_m, omega;
  complex_t t, u;

  bit_reversal_permutation(A);
  
  for(s = 1; s <= LOG2LEN; s++) {
    m = 1<<s;
    half_m = m/2;
    omega_m = COMPLEX(sinf(2*pi/m), cosf(2*pi/m));

    for(k = 0; k < 1<<LOG2LEN; k += m) {
      complex_t omega = COMPLEX(1.0f, 0.0f);

      for(j = 0; j < half_m; j++) {
	t = COMPLEX_MUL(omega, A[k + j + half_m]);
	u = A[k + j];

	A[k + j] = COMPLEX_ADD(u, t);
	A[k + j + half_m] = COMPLEX_ADD(u, -t);
	omega = COMPLEX_MUL(omega, omega_m);
      }
    }
  }
}

int reverse_index(int I)
{
  int j = 0, result = 0;
  for(j = 0; j < LOG2LEN; j++) {
    result = (result<<1) | (I & 1);
    I >>= 1;
  }
  return result;
}

void reverse(complex_t *data)
{
  int i = 0;
  
  for(i = 0; i < 1<<LOG2LEN; i++)
    data[i] = data[reverse_index(i)];
}

int main()
{
  int i = 0;

  printf("Blob.\n");
  
  for(i = 0; i < 1<<LOG2LEN; i++)
    fft_data[i] = COMPLEX(sinf(i*2*pi/32), cosf(i*2*pi/32));
    // fft_data[i] = COMPLEX(1.0f, 0.0f);
    // fft_data[i] = COMPLEX(i & 1 ? 1.0f : -1.0f, 0.0f);
  
  for(i = 0; i < 1<<LOG2LEN; i++)
    printf("Input[%d] = %.3f + i%.3f\n", i, fft_data[i].real, fft_data[i].imag);
  
  fft(fft_data);

  for(i = 0; i < 1<<LOG2LEN; i++)
    printf("Output[%d] = %.3f + i%.3f (%.3f)\n", i, fft_data[i].real, fft_data[i].imag, COMPLEX_ABS(fft_data[i]));
}
