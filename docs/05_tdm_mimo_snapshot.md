[← README](../README.md) · [이전](04_doppler_interpolation.md) · [다음](06_sample_measurement.md)

# 2.5 TDM-MIMO Snapshot 생성

2D-MUSIC을 적용할 때 12x1의 공분산 행렬을 구성하기 위해 loop(3개의 Tx안테나를 이용한 TDM-MIMO방식이므로 한 loop안에 3개의 Chirp이 들어감)별로 하나의 Snapshot을 구성해야한다. 이때 TDM-MIMO방식을 사용하기 때문에 Chirp별로 Chirp Time만큼 시간 차이가 나 Tx별로 위상에 차이가 생긴다. 그 식은 다음과 같다.

$∆\phi =2π * f_d * T_c$

따라서 2번 Tx에는 $\Delta \phi$만큼, 3번 Tx에는  $2\Delta \phi$만큼 역으로 빼주어야 정확한 Snapshot을 구성할 수 있다. 이를 MATLAB코드에도 적용하였다. 또한, 이 식에 사용되는 ${f_{d}}$ 즉 도플러 주파수는 31번의 loop에 대해 평균을 적용하여 도플러 주파수를 구했다.

---

[← README](../README.md) · [이전](04_doppler_interpolation.md) · [다음](06_sample_measurement.md)
