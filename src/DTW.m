%% Compare_Traj_3D_fromMAT.m
% 두 개의 .mat 파일에서 3D 궤적 [x y z]을 로드하여 DTW로 비교하고 시각화
% 지원 입력 형태:
%   (1) struct traj.x, traj.y, traj.z (예: traj.x_cm 등도 자동 인식)
%   (2) 개별 변수 x,y,z
%   (3) [N x 3] 행렬 변수
% 통계/ML Toolbox의 pdist2 사용

clear; clc;

%% ===== 사용자 입력 =====
fileA = 'B1.mat';
fileB = 'B2.mat';

% 유사도 정규화 상수(샘플이 300개라면 300 권장)
norm_const = 50;

%% ===== 로드 & 전처리 =====
X = load_traj3_from_mat(fileA);   % [Nx x 3] = [x y z]
Y = load_traj3_from_mat(fileB);   % [Ny x 3] = [x y z]

% NaN 행 제거
X = X(~any(isnan(X),2), :);
Y = Y(~any(isnan(Y),2), :);

% 최소 길이 체크
if size(X,1) < 2 || size(Y,1) < 2
    error('유효 샘플이 너무 적습니다. 각 파일에 최소 2개 이상의 샘플이 필요합니다.');
end

% 길이 정보 출력(참고)
fprintf('Len(A)=%d, Len(B)=%d\n', size(X,1), size(Y,1));

%% ===== DTW 실행 (xyz) =====
[dist, ix, iy, cnt] = dtw_local_3d(X, Y);

% 기존 스타일: cnt는 비대각선 스텝 수 + N(첫 번째 시퀀스 길이)
cnt = cnt + size(X,1);
sim_score = norm_const / (norm_const + dist);

%% ===== 3D 플롯 =====
figure('Name','3D Trajectories');
scatter3(X(:,1), X(:,2), X(:,3), 6, 'filled'); hold on;
scatter3(Y(:,1), Y(:,2), Y(:,3), 6, 'filled');
grid on; axis equal;
axis([0 1 -0.8 0.8 -0.8 0.8]);
xlabel('X'); ylabel('Y'); zlabel('Z');
title('3D Trajectories (no time axis)');
legend('Traj A','Traj B','Location','best');

txt = sprintf(['DTW distance = %.6f\n',...
               'Warping length = %d\n',...
               'Similarity = %.6f (norm=%d)'], ...
               dist, cnt, sim_score, norm_const);
annotation('textbox', [0.15 0.01 0.7 0.12], 'String', txt, ...
    'EdgeColor','none','HorizontalAlignment','center','FontSize',11);

%% ===== 워핑 경로 플롯 =====
figure('Name','DTW Warping Path');
plot(ix, iy, 'r'); grid on; axis tight;
xlabel('Index in A'); ylabel('Index in B');
title('DTW Warping Path: A vs B');

%% ───────────── Local Functions ─────────────
function T = load_traj3_from_mat(fname)
% .mat에서 [x y z] 반환
% 우선순위:
%  1) S.traj 구조체 내 후보 필드 조합
%  2) 개별 변수 x,y,z
%  3) [N x 3] 행렬 변수

    S = load(fname);

    % 1) 'traj' 구조체 패턴
    if isfield(S, 'traj')
        TT = S.traj;
        if isstruct(TT)
            x = try_fields(TT, {'x','x_cm','x_m','x_mm','X'});
            y = try_fields(TT, {'y','y_cm','y_m','y_mm','Y'});
            z = try_fields(TT, {'z','z_cm','z_m','z_mm','Z'});
            T = cat_traj3(x,y,z,fname);
            return;
        elseif isnumeric(TT) && size(TT,2) >= 3
            T = ensure_xyz(TT(:,1:3));  return;
        end
    end

    % 2) 개별 변수 x,y,z
    x = try_fields(S, {'x','X','pos_x','px'});
    y = try_fields(S, {'y','Y','pos_y','py'});
    z = try_fields(S, {'z','Z','pos_z','pz'});
    if ~isempty(x) && ~isempty(y) && ~isempty(z)
        T = cat_traj3(x,y,z,fname);  return;
    end

    % 3) [N x 3] 행렬 변수 검색
    fn = fieldnames(S);
    for k = 1:numel(fn)
        v = S.(fn{k});
        if isnumeric(v) && ismatrix(v) && size(v,2) >= 3 && size(v,1) >= 2
            T = ensure_xyz(v(:,1:3));  return;
        end
    end

    error('파일 %s 에서 [x y z] 형태의 궤적을 찾을 수 없습니다.', fname);
end

function out = try_fields(S, candidates)
% 구조체/워크스페이스에서 후보 필드/변수명 탐색
    out = [];
    if isstruct(S)
        for i = 1:numel(candidates)
            f = candidates{i};
            if isfield(S, f)
                out = S.(f);
                if isrow(out), out = out.'; end
                return;
            end
        end
    else
        for i = 1:numel(candidates)
            f = candidates{i};
            if isfield(S, f)
                out = S.(f);
                if isrow(out), out = out.'; end
                return;
            end
        end
    end
end

function T = cat_traj3(x,y,z,fname)
% x,y,z를 [N x 3]로 결합하며 길이 체크
    if isempty(x) || isempty(y) || isempty(z)
        error('파일 %s: x/y/z 중 일부가 비어 있습니다.', fname);
    end
    n = unique([numel(x), numel(y), numel(z)]);
    if numel(n) ~= 1
        error('파일 %s: 길이 불일치. x=%d, y=%d, z=%d', ...
              fname, numel(x), numel(y), numel(z));
    end
    T = [x(:), y(:), z(:)];
end

function A = ensure_xyz(A)
% 앞 3열만 취하고 행 방향 정리
    if size(A,2) > 3, A = A(:,1:3); end
end

function [dist, ix, iy, cnt] = dtw_local_3d(X, Y)
% 3D DTW (시간축 없음)
% 입력:
%   X: [Nx x 3], Y: [Ny x 3]
% 출력:
%   dist: 누적 최소 비용
%   ix, iy: 워핑 경로 인덱스
%   cnt: 비대각선 이동(삽입/삭제) 횟수

    Nx = size(X,1); Ny = size(Y,1);
    D  = pdist2(X, Y, 'euclidean');

    C   = inf(Nx, Ny);
    ptr = zeros(Nx, Ny);  % 1:diag, 2:up, 3:left

    C(1,1) = D(1,1);
    for i = 2:Nx, C(i,1) = C(i-1,1) + D(i,1); ptr(i,1) = 2; end
    for j = 2:Ny, C(1,j) = C(1,j-1) + D(1,j); ptr(1,j) = 3; end

    for i = 2:Nx
        for j = 2:Ny
            [mval, k] = min([C(i-1,j-1), C(i-1,j), C(i,j-1)]);
            C(i,j)   = D(i,j) + mval;
            ptr(i,j) = k;
        end
    end

    dist = C(Nx,Ny);

    % 백트래킹
    maxLen = Nx + Ny;
    ix = zeros(maxLen,1); iy = zeros(maxLen,1);
    i = Nx; j = Ny; p = 1; cnt = 0;
    while true
        ix(p) = i; iy(p) = j;
        if i==1 && j==1, break; end
        switch ptr(i,j)
            case 1, i=i-1; j=j-1;
            case 2, i=i-1; cnt=cnt+1;
            case 3, j=j-1; cnt=cnt+1;
        end
        p = p + 1;
    end
    ix = flipud(ix(1:p));  iy = flipud(iy(1:p));
end
