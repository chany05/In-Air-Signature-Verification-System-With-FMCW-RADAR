%% 
clear;

%    addpath('tools');
%    addpath('dataset');
    
    %% ===========파라미터 정의================== 
    numADCsamples = 512;
    numRx = 4;
    numTx = 3;
    numLoops = 31;
    Fs = 8.26e6;                 % ADC sampling rate
    slope = 6.2498e13;           % Hz/s
    f = 62e9;                    %Hz
    ChirpTime = 71e-6;           %s
    PRI = numTx * ChirpTime;     %s -> TDM은 PRI에 TX개수만큼 곱함
    CPI = PRI * numLoops;        %s 
    
    load("bg.mat");
    load("ANT_Bias.mat");
    
    
    c = 299792458;
    lambda = c / (f);
    Roi_range = [0 3];
    
    
    bias = zeros(24,1);
    
    filename = "0827_testa_Raw_0.bin";
    %filename = "adc_data_azi40_Raw_0.bin";

    %% ============데이터큐브 생성===============
    [retVal] =  readDCA1000(filename, numADCsamples, numRx);
    numChirps = size(retVal,2)/numADCsamples;
    numFrame = numChirps/(numTx*numLoops);
    Data_Cube = reshape(retVal, numRx, numADCsamples, numChirps); % cube [Rx, SampleNum, ChirpN]
    clear retVal, clear filename;
    
    % TX별로 묶기
    Tx_idx{1} = 1:3:numChirps;
    Tx_idx{2} = 2:3:numChirps;
    Tx_idx{3} = 3:3:numChirps;

    x_deg =zeros(1,numFrame);
    y_deg =zeros(1,numFrame);
    z_deg =zeros(1,numFrame);

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
    
    Xf = fft(Xn,N_fft,3); %[Tx,Rx, RangeBin, numloop*frame]
    
    w = [];



    Xf = reshape(Xf, numTx, numRx, N_fft, numLoops, numFrame);
    Xf = permute(Xf, [3, 4, 1, 2, 5]);    % Xf_Doppler_in  [N_fft, N_loop, numTx, numRx, numFrames]
    
    %% ----------
    interpFactor = 4;  % 2~8 권장
    interp_range_axis = linspace(range_axis(1), range_axis(end), numel(range_axis)*interpFactor);
    
    Peak_idx_perchirp = zeros(numFrame,numLoops);
    %peak_idx = zeros(numFrame,1);
    
    %frame = 100;
    
    %for frame = 1:numFrame
    Rxx = 0; 
    R = 0; Rbg = 0;
    
    M   = 4; %가상배열 크기
    % ==== 파라미터 (기존 유지) ====
    guard = 0;
    train = 5;                       % 좌우 각각 10 → 전체 N = 20
    k_os  = 9;                       % ~0.8*N 권장 (15~18 사이 튜닝)
    alpha_os = 1.0;                    % OS-CFAR 스케일(선형). Pfa에 맞춰 튜닝/시뮬 추천.
    
    interpFactor = 4;
    interp_range_axis = linspace(range_axis(1), range_axis(end), numel(range_axis)*interpFactor);
    
    
    
    Peak_idx_perchirp = zeros(numFrame,numLoops);
    
    %frame = 100;
    
    % === 공분산 누적 ===
    M   = 4;
    Rxx = zeros(M,M,'like',Xf);
    Rbg = zeros(M,M,'like',Xf);
    rbinAll = zeros(1,numLoops);
    YcorrAll = zeros(numLoops, numTx*numRx, N_fft);
    ga = 0.90;
    bgRespMag = [];
    rbinlast = zeros(1, numFrame);
    %% +===================================
    rbinlast(1) = 16;
    roi_start = rbinlast(1)-1;
    roi_end = rbinlast(1)+1;

    % 보간축에서의 ROI 인덱스
    roi_start_i = 1 + interpFactor*(roi_start-1);
    roi_end_i   = interpFactor*roi_end;


    azimuth = zeros(1,numFrame);
    elevation = zeros(1,numFrame);

    %% ========================================
    elevation(1) = 0;

    phi = -azimuth(1);
    theta = elevation(1);

    for frame = 1:numFrame

        for loop = 1:numLoops
            Sy  = squeeze(Xf(:,    loop, :, :, frame));   % [N_fft, Tx, Rx]
            Y = reshape(permute(Sy,  [2 3 1]), [numTx*numRx, N_fft]);



            Yc = Y .* conj(ant_bias);   % [M x N_fft]
            Bc = squeeze(BcorrAll(loop,:,:));

            alpha = (Bc(:)'*Yc(:)) / (Bc(:)'*Bc(:) + eps);
            Ycorr = Yc - Bc; % - alpha*Bc;


            %%
            %{
            if(~isempty(w))
                for r = 1:N_fft
                    Y_mvdr(r) = w' * Ycorr(:,r); 
                end
            else
                Y_mvdr = Ycorr(1,:);
            end

            if isempty(bgRespMag)
                bgRespMag = Y_mvdr;
            else
                bgRespMag = ga*bgRespMag + (1-ga)*Y_mvdr;
            end
            Yemi = Y_mvdr;% - bgRespMag;

            %%
            %}
            %{
            if isempty(bgRespMag)
                bgRespMag = Ycorr;
            else
                bgRespMag = ga*bgRespMag + (1-ga)*Ycorr;
            end
            %}
            Yemi = Ycorr;% - bgRespMag;
            %}

            P_cur = sum(abs(Yemi).^2, 1);  % 1 x N_fft
            
            %% --- 보간 + OS-CFAR ---
            P_cur_i = interp1(range_axis, P_cur, interp_range_axis, 'pchip', 'extrap');
            P_cur_i(~isfinite(P_cur_i)) = min(P_cur_i(isfinite(P_cur_i)));
        
            cfar_mask_i = cfar(P_cur_i, guard, train, k_os, alpha_os);
        
            roi_mask = false(size(cfar_mask_i));
            roi_mask(roi_start_i:min(roi_end_i, numel(cfar_mask_i))) = true;
        
            idx_i = find(cfar_mask_i & roi_mask);
            if isempty(idx_i)
                [~, tmax] = max(P_cur_i(roi_start_i:roi_end_i));
                idx_i = roi_start_i + tmax - 1;
            else
                idx_i = idx_i(1);
            end
            %%
            rbins = round(1 + (idx_i-1)/interpFactor);
            rbins = max(1, min(N_fft, rbins));
            Peak_idx_perchirp(frame, loop) = rbins;
            rbinAll(loop) = rbins;
            YcorrAll(loop,:,:) = Ycorr;
            
        
    
        end
        rbinmode = mode(rbinAll(rbinAll~=0));
        rbinlast(frame) = rbinmode;
%%      
        %
        
        [azimuth(frame), elevation(frame), x_deg(frame), y_deg(frame), z_deg(frame), fdall(frame), w, x_channel] = ...
            MUSIC(YcorrAll(:,:,:), rbinlast(frame), theta, phi);
        phi = -azimuth(frame);
        theta = elevation(frame);
        %phiall(frame) =phi;


        roi_start = rbinmode-1;
        roi_end = rbinmode+1;
        % 보간축에서의 ROI 인덱스
        roi_start_i = 1 + interpFactor*(roi_start-1);
        roi_end_i   = interpFactor*roi_end;
        %
    end
%%



%%
%
%
fdall_samplerate = 1/0.007;   % ≈ 142.857 Hz
Filtcutoff = 2;         % 컷오프 주파수 [Hz] (원하는 대역에 맞게 조절)
filt_N  = 4;         % 필터 차수

% 정규화 컷오프
Wn = Filtcutoff / (fdall_samplerate/2);

% Butterworth 저역통과 필터 설계
[b_filt,a_filt] = butter(filt_N, Wn, 'low');

% 벡터 x에 대해 필터링
fdall_filt = filtfilt(b_filt,a_filt,fdall);
azimuth = filtfilt(b_filt,a_filt,azimuth);
elevation = filtfilt(b_filt,a_filt,elevation);
x_deg = filtfilt(b_filt,a_filt,x_deg);
y_deg = filtfilt(b_filt,a_filt,y_deg);
z_deg = filtfilt(b_filt,a_filt,z_deg);


%%
figure;
t = 1:numel(azimuth);
scatter(azimuth, elevation, 20, t, 'filled');
colormap turbo; colorbar; ylabel(colorbar,'Frame');
axis([-90 90 -90 90]);
grid on; box on;
xlabel('Azimuth (deg)'); ylabel('Elevation (deg)'); title('Antenna Bias None-removed');
set(gcf,'Color','w');

%%

[rbinint] = interpolation(rbinlast, numFrame, fdall_filt);




x = x_deg.*rbinint;
y = y_deg.*rbinint;
z = z_deg.*rbinint;


save('result.mat', "x","y","z");

%}
%%
%
figure;
hDot  = plot3(NaN, NaN, NaN, 'o', 'MarkerFaceColor','r','MarkerEdgeColor','k'); hold on
box on; xlabel('x'); ylabel('y'); zlabel('z');
grid on; axis([0 1 -0.7 0.7 -0.7 0.7]);   % 데이터 범위에 꼭 맞게
htail = plot3(NaN, NaN, NaN, 'o', 'MarkerFaceColor','b','MarkerEdgeColor','k'); hold on
% 원하는 점에 미리 달기


Ts = 0.007; N = min(numel(azimuth), numel(elevation));

for i = 1:N
    set(hDot,  'XData', x(i),      'YData', y(i), 'ZData', z(i));
    set(htail,  'XData', x(1:i),      'YData', y(1:i), 'ZData', z(1:i));
    drawnow limitrate; pause(Ts);
end
%

%%
%
% 
% absy = squeeze(mean(abs(YcorrAll),[1 2])); %ant / loop mean
% 
% absy = absy + eps;                        % log(0) 방지
% PdB  = 20*log10( absy / max(absy) );      % 상대 파워 dB (0 dB = 최대)
% 
% figure; 
% plot(range_axis, PdB, 'LineWidth', 1.5);
% grid on;
% xlabel('Range (m)');
% ylabel('Power (dB)');
% axis([0 20 -60 0])
% title('Background Processing');
% set(gcf,'Color','w');                     % 흰 배경 (옵션)
% xlim([range_axis(1), range_axis(end)]);




%



































function [azimuth, elevation, x_deg, y_deg, z_deg, fdcorr, w, x_channel] = MUSIC(Ymusic, rbin, theta, phi)
%% Y [loop, ant_idx, Nfft]
%% theta, phi -> theta +-5
%% rbin scalar
%% fd_bias [nfft, tx]
    Ydd = Ymusic;
    numADCsamples = 512;
    numRx = 4;
    numTx = 3;
    numLoops = 31;
    Fs = 8.26e6;                 % ADC sampling rate
    slope = 6.2498e13;           % Hz/s
    f = 62e9;                    %Hz
    ChirpTime = 71e-6;           %s
    PRI = numTx * ChirpTime;     %s -> TDM은 PRI에 TX개수만큼 곱함
    PRF = 1/PRI;
    CPI = PRI * numLoops;        %s 
    c = 299792458;
    lambda = c / (f);
    N_fft = numADCsamples;   
    range_res  = c*Fs/(2*slope*N_fft);      % [m/bin] 거리 해상도
    range_axis = (0:N_fft-1) * range_res;   % m 단위 거리 벡터
    dz = lambda/2;
    dy = lambda/2;

    theta2 = theta-4:0.5:theta+4;
    phi2 = phi-4:0.5:phi+4;

    Kc = lambda;
    Virtual_Array = [0,0,1,1;...
                     0,0,1,1;...
                     1,1,1,1;...
                     1,1,1,1];
    a_vec = complex(zeros(numTx*numRx,1));
    a_vec_tmp = complex(zeros(4,4));
    y_corr_idx = [6,9,3,12,4,7,5,8,1,10,2,11];
    Tx_idx = [2,2,2,2,0,0,1,1,0,0,1,1];
    B_corr_idx = [1,4,7,10,2,5,8,11,3,6,9,12];
    n = (0:numLoops-1).';
    winD = reshape(hann(numLoops,"periodic"), [1 numLoops 1 1]);

    fd_Ylist = zeros(N_fft,1);
    
    for Tx = 1:numTx
        rx = (Tx-1)*4+1:Tx*4;
        pow_rx = squeeze(sum(abs(Ymusic(:, B_corr_idx(rx), :)).^2, [1 3]));
        [~,rx0] = max(pow_rx);

 
        s = squeeze(Ymusic(:, B_corr_idx((Tx-1)*4+rx0), rbin));   % [L x 1]
        dop_phi = unwrap(angle(s));
        p   = polyfit(n, dop_phi, 1);
        fd_Ylist(rbin,Tx) = p(1) / (2*pi*PRI);
    end

    fdcorr = mean(fd_Ylist(rbin,:),2);% - fd_bias(rbin,:),2);

    W_va = exp( 1j*2*pi * fdcorr * (Tx_idx) * ChirpTime );   % [VA x 1] column
    W_va = permute(W_va, [2 1]);

    Rx = 0;
    for loop = 1:numLoops
        x_channel = (squeeze(Ymusic(loop,y_corr_idx, rbin))).';
        x_sum(:,loop) = x_channel .* W_va;
        % x_channel = x_channel - mean(x_channel, 1);
    end

    X_0 = x_sum - mean(x_sum,2);
    Rx = (X_0 * X_0');
    Rx = Rx / numLoops;
    Rx = (Rx + Rx')/2; 

    [U, Dv] = eig(Rx, 'vector');
    [~, ord] = sort(real(Dv), 'descend');
    U = U(:, ord);
    K=1;

    Un = U(:, K+1:end);
    Pn = Un * Un';

    P_music = zeros(numel(theta2),numel(phi2));
    
    for i = 1:numel(theta2)
        for j = 1:numel(phi2)
            ang1 = theta2(i);
            ang2 = phi2(j);
            cnt=1;
            a_vec = [];
            for Mz = 1:4
                for My = 1:4
                    steering = exp(1j*(2*pi/Kc)*(dy*(My-1)*cos(deg2rad(ang1))*sin(deg2rad(ang2))...
                             + dz*(Mz-1)*sin(deg2rad(ang1)) ) );
                    a_vec_tmp(Mz,My) = steering*Virtual_Array(Mz,My);
                    if(a_vec_tmp(Mz,My) ~= 0)
                        a_vec(cnt) = a_vec_tmp(Mz,My);
                        cnt=cnt+1;
                    end
                end
            end

            denom = a_vec * Pn * a_vec';
            P_music(i,j) = real(1 ./ max(denom, eps));
        end
    end

    peaks_mask = imregionalmax(P_music);

    [ti, pj] = find(peaks_mask);          % 행=theta index, 열=phi index
    vals = P_music(peaks_mask);
    [~, ord] = sort(vals, 'descend');
    ti = ti(ord); pj = pj(ord);

    peaks = [ti(1), pj(1)];

    %%
    azimuth   = -phi2(peaks(2));  % 좌우
    elevation = theta2(peaks(1));  % 상하
    

    
    x_deg = (cos(deg2rad(theta2(peaks(1))))*cos(deg2rad(phi2(peaks(2)))));
    y_deg = (cos(deg2rad(theta2(peaks(1))))*sin(deg2rad(phi2(peaks(2)))));
    z_deg = (sin(deg2rad(theta2(peaks(1)))));
    %% 나중에 rbinint/rbin 곱해줘야 interpolation가능
    
    cnt = 1;
    for Mz = 1:4
        for My = 1:4
            steering = exp(1j*(2*pi/Kc)*(dy*(My-1)*cos(deg2rad(theta2(peaks(1))))*sin(deg2rad(phi2(peaks(2))))...
                     + dz*(Mz-1)*sin(deg2rad(theta2(peaks(1))))) );
            a_vec_tmp(Mz,My) = steering*Virtual_Array(Mz,My);
            if(a_vec_tmp(Mz,My) ~= 0)
                a_vec(cnt) = a_vec_tmp(Mz,My);
                cnt=cnt+1;
            end
        end
    end

    [w] = MVDR(a_vec', Rx); %% [6,9,3,12,4,7,5,8,1,10,2,11];

    w_idx = [9 11 3 5 7 1 6 8 2 10 12 4];

    w = w(w_idx);

end
















%%
function [rbinint] = interpolation(rbinlast, numFrame, fdall)



    %% ===========파라미터 정의================== 
    numADCsamples = 512;
    numRx = 4;
    numTx = 3;
    numLoops = 31;
    Fs = 8.26e6;                 % ADC sampling rate
    slope = 6.2498e13;           % Hz/s
    f = 62e9;                    %Hz
    ChirpTime = 71e-6;           %s
    PRI = numTx * ChirpTime;     %s -> TDM은 PRI에 TX개수만큼 곱함
    PRF = 1/PRI;
    CPI = PRI * numLoops;        %s 
    periodicity = 7e-3;
    
    c = 299792458;
    lambda = c / f;
    Vd = lambda/2*fdall;

    cnt = 0;
    bin_idx = 1;
    R_pos(1) = (rbinlast(1)-1) * 0.0387 + 0.0387/2;
    cntAll=0;
    avgR = 0;
    alpha=zeros(1,bin_idx);
    init_pos(1) = (rbinlast(1)-1) * 0.0387; 
    

    for frame = 1:numFrame-1
        if (rbinlast(frame) ~= rbinlast(frame+1))
            cnt = cnt+1;
            cntAll(bin_idx) = cnt;
            cnt = 0;
            bin_idx = bin_idx+1;
            if(rbinlast(frame) > rbinlast(frame+1))
                init_pos(bin_idx-1) = rbinlast(frame) * 0.0387;

            else
                if(frame == 1)
                    init_pos(bin_idx-1) = rbinlast(frame) * 0.0387;
                else
                    init_pos(bin_idx-1) = rbinlast(frame-1) * 0.0387;
                end

            end
            
        else
            cnt = cnt + 1;
        end
        
    end
    %% init_pos(bin_idx) = 
    cntAll(bin_idx) = numFrame - sum(cntAll);
    %bin_idx = bin_idx-1;
    %bin_idx=bin_idx-1;
    frame = 1;
    A = zeros(1,bin_idx);
    absA = zeros(1,bin_idx);
    mask = false(1,bin_idx);

    for i = 1:bin_idx
        for j = 1:cntAll(i)
            A(i) = A(i) + Vd(frame) * periodicity;
            absA(i) = absA(i) + abs(Vd(frame)) * periodicity;
            frame = frame + 1;
        end
        
        if((abs(A(i)) / (absA(i)+1e-12) < 0.35))
            mask(i) = true;
        else
            mask(i) = false;
        end
        alpha(i) = 0.0387 / absA(i);
    end

    if(A(bin_idx-1) > 0)
        init_pos(bin_idx) = init_pos(bin_idx-1) + 0.0387;
    else
        init_pos(bin_idx) = init_pos(bin_idx-1) - 0.0387;
    end
    [maxval,~] = max(absA);

    
    
    cntAll(bin_idx) = cntAll(bin_idx)-1;
    frame=2;
    for i = 1:bin_idx
        if(mask(i) == true)
            beta(i) = absA(i)/(maxval+1e-12);
        end
        R_pos(frame-1) = init_pos(i);
        for j = 1:cntAll(i)
            if(mask(i) == false)
                R_pos(frame) = R_pos(frame-1)+Vd(frame)*periodicity*alpha(i);
            else
                alpha_tmp = alpha(i) * beta(i);
                R_pos(frame) = R_pos(frame-1)+Vd(frame)*periodicity*alpha_tmp;
            end
            rbinint(frame) = R_pos(frame);

            frame = frame + 1;
            if(frame ==numFrame)
                
            end
        end
    end
    rbinint(1) = init_pos(1);
end















function detections = cfar(signal, guard, train, k, alpha)
    % signal: 입력 1D 전력 벡터
    % guard, train: 가드셀, 훈련셀 개수
    % k: 서수 (훈련셀 수 중 몇번째)
    % alpha: 스케일 계수 (Pfa 맞추는 값)

    N = length(signal);
    detections = zeros(1,N);

    for i = (train+guard+1):(N-train-guard)
        % 훈련셀 인덱스
        idx = [ (i-train-guard):(i-guard-1), (i+guard+1):(i+guard+train) ];
        ref_cells = signal(idx);

        % 정렬 후 k번째 값
        ref_sorted = sort(ref_cells);
        noise_level = ref_sorted(k);

        % 임계치
        threshold = alpha * noise_level;

        % CUT와 비교
        if signal(i) > threshold
            detections(i) = i;
        end
    end
end


function [w] = MVDR(a0, Rx)
    w = (Rx \ a0) / (a0' * (Rx \ a0));   % MVDR weight (안정적 선형해법)\
end


%%% Command to run in Matlab GUI -readDCA1000('<ADC capture bin file>') 
function [retVal] = readDCA1000(fileName, numADCSamples, numRX)

%% global variables
% change based on sensor config
numADCBits = 16; % number of ADC bits per sample
numLanes = 2; % do not change. number of lanes is always 2
isReal = 0; % set to 1 if real only data, 0 if complex data0
%% read file
% read .bin file
fid = fopen(fileName,'r');
adcData = fread(fid, 'int16');
% if 12 or 14 bits ADC per sample compensate for sign extension
if numADCBits ~= 16
    l_max = 2^(numADCBits-1)-1;
    adcData(adcData > l_max) = adcData(adcData > l_max) - 2^numADCBits;
end
fclose(fid);
fileSize = size(adcData, 1);
% real data reshape, filesize = numADCSamples*numChirps
if isReal
    numChirps = fileSize/numADCSamples/numRX;
    LVDS = zeros(1, fileSize);
    %create column for each chirp
    LVDS = reshape(adcData, numADCSamples*numRX, numChirps);
    %each row is data from one chirp
    LVDS = LVDS.';
else
    % for complex data
    % filesize = 2 * numADCSamples*numChirps
    numChirps = fileSize/2/numADCSamples/numRX;
    LVDS = zeros(1, fileSize/2);
    %combine real and imaginary part into complex data
    %read in file: 2I is followed by 2Q
    counter = 1;
    for i=1:4:fileSize-1
        LVDS(1,counter) = adcData(i) + sqrt(-1)*adcData(i+2); 
        LVDS(1,counter+1) = adcData(i+1)+sqrt(-1)*adcData(i+3); 
        counter = counter + 2;
    end
    % create column for each chirp
    LVDS = reshape(LVDS, numADCSamples*numRX, numChirps);
    %each row is data from one chirp
    LVDS = LVDS.';
end
%organize data per RX
adcData = zeros(numRX,numChirps*numADCSamples);
for row = 1:numRX
    for i = 1: numChirps
        adcData(row, (i-1)*numADCSamples+1:i*numADCSamples) = LVDS(i, (row-1)*numADCSamples+1:row*numADCSamples);
    end
end
% return receiver data
retVal = adcData;

end