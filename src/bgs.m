clear; addpath('tools');
addpath('dataset');

%% ===========파라미터 정의==================
filename = "0818_move_bg_Raw_0.bin";
load("ANT_Bias.mat");

numADCsamples = 512;
numRx = 4;
numTx = 3;
numLoops = 31;
Fs = 8.26e6;                 % ADC sampling rate
slope = 6.2498e13;           % Hz/s
f = 60e9;                    %Hz
ChirpTime = 71e-6;           %s
PRI = numTx * ChirpTime;     %s -> TDM은 PRI에 TX개수만큼 곱함
CPI = PRI * numLoops;        %s 

c = 299792458;
lambda = c / (f+2e9);
Roi_range = [0 3];

%% ============데이터큐브 생성===============
[retVal] = test(filename, numADCsamples, numRx);
numChirps = size(retVal,2)/numADCsamples;
numFrame = numChirps/(numTx*numLoops);
Data_Cube = reshape(retVal, numRx, numADCsamples, numChirps); % cube [Rx, SampleNum, ChirpN]
clear retVal, clear filename;

% TX별로 묶기
Tx_idx{1} = 1:3:numChirps;
Tx_idx{2} = 2:3:numChirps;
Tx_idx{3} = 3:3:numChirps;

IQ_data = zeros(numTx, numRx, numADCsamples, numLoops*numFrame, 'like', Data_Cube);

for i = 1:numTx
    IQ_data(i, :, :, :) = Data_Cube(:, :, Tx_idx{i});                   % Tx별 슬라이스 복사
end

win3 = reshape(hann(numADCsamples,"periodic"), [1 1 numADCsamples 1]);  % 1x1xN x1
Xn   = IQ_data .* win3;                                                 %복소 IQ에 직접 윈도잉

%% ============== FFT ========================


%RangeFFT
N_fft = numADCsamples;                  % FFT 포인트 수 (보통 ADC 샘플 개수)
range_res  = c*Fs/(2*slope*N_fft);      % [m/bin] 거리 해상도
range_axis = (0:N_fft-1) * range_res;   % m 단위 거리 벡터

bg_Xf = fft(Xn,N_fft,3); %[Tx,Rx, RangeBin, numloop*frame]
bg_Xf = reshape(bg_Xf, numTx, numRx, N_fft, numLoops, numFrame);
bg_Xf = permute(bg_Xf, [3, 4, 1, 2, 5]);    %Xf_Doppler_in  [N_fft, N_doppler, numTx, numRx, numFrames]

B_corr_idx = [1,4,7,10,2,5,8,11,3,6,9,12];

fd_bias = zeros(1,numTx);
n = (0:numLoops-1).';
roi_end = 20;

for frame = 1:numFrame

    for loop = 1:numLoops
        Sbg = squeeze(bg_Xf(:, loop, :, :, frame));   % [N_fft, Tx, Rx]
        B = reshape(permute(Sbg, [2 3 1]), [numTx*numRx, N_fft]);
        Bcorr = B .* conj(ant_bias);
        BcorrAll(loop,:,:) = Bcorr;
    end
    for Tx = 1:numTx
        rx = (Tx-1)*4+1:Tx*4;
        pow_rx = squeeze(sum(abs(BcorrAll(:, B_corr_idx(rx), :)).^2, [1 3]));
        [~,rx0] = max(pow_rx);
        fd_list = zeros(N_fft,1);
        for ii = 1:roi_end
            s = squeeze(BcorrAll(:, (Tx-1)*4+rx0, ii));   % [L x 1]
            phi = unwrap(angle(s));
            p   = polyfit(n, phi, 1);
            fd_list(ii) = p(1) / (2*pi*PRI);
            fd_bias(ii, Tx) = fd_list(ii);
        end
    end


    
end







% winD = reshape(hann(numLoops,"periodic"), [numLoops 1 1]);
% for frame = 1:numFrame
%     for loop = 1:numLoops
%         Sbg = squeeze(bg_Xf(:, loop, :, :, frame));   % [N_fft, Tx, Rx]
%         B = reshape(permute(Sbg, [2 3 1]), [numTx*numRx, N_fft]);
%         Bcorr = B .* conj(ant_bias);
%         BcorrAll(loop,:,:) = Bcorr;
%     end
%     xw = BcorrAll .* winD;
%     XD = fftshift(fft(xw, numLoops, 1),1); %XD = [N_dop, ant, N_fft]
% 
% 
% 
%     % for ant = 1:numTx*numRx
%     %     for i = 1:N_fft
%     %         pdop = abs(XD(:,ant,i)).^2;
%     %         [~, p_hat] = max(pdop);
%     %         p = (-floor(numLoops/2):ceil(numLoops/2)-1);
%     %         fD_hat = p(p_hat) / (numLoops * PRI); % [Hz]
%     %         fdall(frame, ant, i) = fD_hat;
%     %     end
%     % end
% end
save("bg.mat","bg_Xf","BcorrAll");
%