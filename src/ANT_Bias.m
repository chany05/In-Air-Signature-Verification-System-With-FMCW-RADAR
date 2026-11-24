%% 
%function CFAR_MUSIC_GRAPH(N)
N = 0;
    addpath('tools');
    addpath('dataset');
    
    %% ===========파라미터 정의================== 
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
    
    load("bg.mat");
    
    
    c = 299792458;
    lambda = c / (f+2e9);
    Roi_range = [0 3];
    
    roi_start = 1;
    roi_end = 100;
    
    bias = zeros(24,1);
    
    filename = "0818azi+0_Raw_0.bin";
    %filename = "adc_data_azi40_Raw_0.bin";
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
    
    Xf = fft(Xn,N_fft,3); %[Tx,Rx, RangeBin, numloop*frame]
    
    bg_Xf = reshape(bg_Xf, numTx, numRx, N_fft, numLoops, numFrame);
    bg_Xf = permute(bg_Xf, [3, 4, 1, 2, 5]);
    Xf = reshape(Xf, numTx, numRx, N_fft, numLoops, numFrame);
    Xf = permute(Xf, [3, 4, 1, 2, 5]);    % Xf_Doppler_in  [N_fft, N_loop, numTx, numRx, numFrames]
    
    %% ----- [추가] 보간 설정 (플롯 초기화 직후에 넣기) -----
    interpFactor = 4;  % 2~8 권장
    interp_range_axis = linspace(range_axis(1), range_axis(end), numel(range_axis)*interpFactor);
    
    Peak_idx_perchirp = zeros(numFrame,numLoops);
    %peak_idx = zeros(numFrame,1);
    
    frame = 100;
    
    %for frame = 1:numFrame
    Rxx = 0;
    R = 0; Rbg = 0;
    
    M   = 4; %가상배열 크기
    % ==== 파라미터 (기존 유지) ====
    guard = 3;
    train = 20;                       % 좌우 각각 10 → 전체 N = 20
    k_os  = 30;                       % ~0.8*N 권장 (15~18 사이 튜닝)
    alpha_os = 1.0;                   % OS-CFAR 스케일(선형). Pfa에 맞춰 튜닝/시뮬 추천.
    
    interpFactor = 4;
    interp_range_axis = linspace(range_axis(1), range_axis(end), numel(range_axis)*interpFactor);
    
    % 보간축에서의 ROI 인덱스
    roi_start_i = 1 + interpFactor*(roi_start-1);
    roi_end_i   = interpFactor*roi_end;
    
    Peak_idx_perchirp = zeros(numFrame,numLoops);
    
    %frame = 100;
    
    % === 공분산 누적 ===
    M   = 4;
    Rxx = zeros(M,M,'like',Xf);
    Rbg = zeros(M,M,'like',Xf);
    rbinAll = zeros(1,numLoops);
    YcorrAll = zeros(numFrame,numLoops, numTx*numRx, N_fft, 'like', Xf);
    ant_bias = zeros(1,numRx*numTx);
    for frame = 1:numFrame
        for loop = 1:numLoops
            % [N_fft, numTx, numRx]로 잘라오기
            Sbg = squeeze(bg_Xf(:, loop, :, :, frame));   % [N_fft, Tx, Rx]
            Sy  = squeeze(Xf(:,    loop, :, :, frame));   % [N_fft, Tx, Rx]
        
            % [Tx, Rx, N] → [Tx*Rx, N] (tx가 먼저 변하는 순서)
            B = reshape(permute(Sbg, [2 3 1]), [numTx*numRx, N_fft]);
            Y = reshape(permute(Sy,  [2 3 1]), [numTx*numRx, N_fft]);
            
            Ycorr = Y - B;   % [VA x N_fft]
            P_cur = sum(abs(Ycorr).^2, 1);  % 1 x N_fft
        
            % --- 보간 + OS-CFAR ---
            P_cur_i = interp1(range_axis, P_cur, interp_range_axis, 'pchip', 'extrap');
            P_cur_i(~isfinite(P_cur_i)) = min(P_cur_i(isfinite(P_cur_i)));
        
            cfar_mask_i = os_cfar(P_cur_i, guard, train, k_os, alpha_os);
        
            roi_mask = false(size(cfar_mask_i));
            roi_mask(roi_start_i:min(roi_end_i, numel(cfar_mask_i))) = true;
        
            idx_i = find(cfar_mask_i & roi_mask);
            if isempty(idx_i)
                [~, tmax] = max(P_cur_i(roi_start_i:roi_end_i));
                idx_i = roi_start_i + tmax - 1;
            else
                idx_i = idx_i(1);
            end
        
            rbin = round(1 + (idx_i-1)/interpFactor);
            rbin = max(1, min(N_fft, rbin));
            Peak_idx_perchirp(frame, loop) = rbin;
            
            %rbin=5;  % (디버깅용 강제 고정) 
            rbinAll(loop) = rbin;
            YcorrAll(frame,loop,:,:) = Ycorr;
            % --- 가상 배열 스냅샷(예: (1,1) (1,4) (2,1) (2,4)) ---
            % permute([2 3 1])이므로 k = tx + (rx-1)*numTx
        end
    rbinmode = mode(rbinAll(rbinAll~=0));
    end
%%
    y_ref = squeeze(YcorrAll(:,:,1,rbinmode));
    y_sel = squeeze(YcorrAll(:,:,:,rbinmode));
    y_sel = mean(y_sel, [1 2]);
    y_ref = mean(y_ref, [1 2]);

    %ant_bias = squeeze(y_sel * conj(y_ref));
    den = sum(abs(y_ref).^2);            % 스칼라
    ant_bias   = squeeze((y_sel * conj(y_ref)) / max(den, eps));  % [Mx1] 복소 이득
    save("ant_bias.mat", 'ant_bias');

    
    
    
    



