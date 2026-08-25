%% AY Last Edit 08-25-26
% Notes: 
% 1. Gap interpolation + noise on raw traces
% 2. De-jittering
% 3. Normalization (∆F/F0)
% 4. Interactive review & exclusion
% 5. Mean calculation
% 6. Downsampling
% 7. Peak kinetics analysis

close all;
clear;

%% Parameters
nChan = 3;           % Number of acquisition channels
photo_Chan = 3;      % Identifier of green photometry channel

photo_start = 100;   % ms
photo_length = 2200; % ms
photo_gap = 100;     % ms

stim_start = 1000;   % ms (Odd sweeps)
jitter_length = 100; % ms

red_freq = 50;       % Hz reduced frequency for output

%% Import AxoGraph X Data
defaultDir = '/Volumes/ANDREW_DATA/2026/Data/01_Jan/Jan 23, 2026/';
[data, hd] = importaxographx(defaultDir);

if isempty(data)
    return; % Exit if user cancelled file selection
end

acq_freq = 1 / (data(end, 1) / size(data, 1));
nSweeps = (size(data, 2) - 1) / nChan;

data_time = data(:, 1); % First column time data
photo_count = floor((size(data, 1) / acq_freq * 1000 - photo_start) / (photo_length + photo_gap));

% Pre-allocate photometry traces matrix
data_photo = zeros(size(data, 1), nSweeps);
for i = 1 : nSweeps
    data_photo(:, i) = data(:, 1 + i * nChan); % Separates photometry traces from [data]
end

%% Step 1: Shutter-Off Masking & Noise-Matched Gap Interpolation (On Raw Data)
for i = 1 : size(data_photo, 2) % Loop each sweep
    
    % Mask recording start to initial shutter opening
    idx_init_end = round((photo_start + 20) / 1000 * acq_freq);
    data_photo(1 : idx_init_end, i) = NaN;
    
    % --- FIXED NOISE ESTIMATION ---
    % Anchor noise calculation to a stable early light window (e.g., 150ms to 900ms)
    % so it never shifts into shutter-closed gaps when stim_start changes.
    stable_noise_win_ms = [photo_start + 50, min(stim_start - 50, 950)]; 
    idx_base_start = round(stable_noise_win_ms(1) / 1000 * acq_freq);
    idx_base_end   = round(stable_noise_win_ms(2) / 1000 * acq_freq);
    
    base_segment   = data_photo(idx_base_start : idx_base_end, i);
    baseline_noise_std = std(detrend(base_segment), 'omitnan');

    % Interpolate between photometry pulses with noise
    for j = 1 : photo_count - 1
        x1 = round((photo_start + j * photo_length + (j - 1) * photo_gap - 50) / 1000 * acq_freq);
        x2 = round((photo_start + j * photo_length + (j - 1) * photo_gap) / 1000 * acq_freq);
        x_start = round((x1 + x2) / 2);
              
        y_start = mean(data_photo(x1 : x2, i), 'omitnan');
        
        x3 = round((photo_start + j * photo_length + j * photo_gap + 50) / 1000 * acq_freq);
        x4 = round((photo_start + j * photo_length + j * photo_gap + 100) / 1000 * acq_freq);
        x_end = round((x3 + x4) / 2);
              
        y_end = mean(data_photo(x3 : x4, i), 'omitnan');
        
        m = (y_end - y_start) / (x_end - x_start); % Gradient
        c = y_start - (x_start * m);               % Offset
        
        k_range = x_start : x_end;
        num_pts = length(k_range);
        
        % Generate Gaussian noise matching clean baseline variance
        noise = randn(num_pts, 1) * baseline_noise_std;
        
        % Linear trend + baseline noise
        data_photo(k_range, i) = (m * k_range' + c) + noise;
    end
        
    % Mask final shutter closure to end of recording
    idx_final_start = round((photo_start + photo_count * photo_length + (photo_count - 1) * photo_gap - 20) / 1000 * acq_freq);
    data_photo(idx_final_start : end, i) = NaN;
end

%% Step 2: De-Jitter Sweeps (Odd/Even Alignment)
pts_jitter = round(jitter_length / 1000 * acq_freq);
nPointsDejit = size(data_photo, 1) - pts_jitter;
data_photo_dejit = zeros(nPointsDejit, size(data_photo, 2));

for i = 1 : size(data_photo, 2)
    if mod(i, 2) == 1 % Odd sweeps
        data_photo_dejit(:, i) = data_photo(1 : end - pts_jitter, i);
    else              % Even sweeps
        data_photo_dejit(:, i) = data_photo(pts_jitter + 1 : end, i);
    end
end
data_time_dejit = data_time(1 : nPointsDejit);

%% Step 3: Normalize Sweeps (ΔF/F0)
data_photo_norm_dejit = zeros(size(data_photo_dejit));
for i = 1 : size(data_photo_dejit, 2)
    idx_f0_start = round(max(photo_start + 50, stim_start - 200) / 1000 * acq_freq);
    idx_f0_end   = round(stim_start / 1000 * acq_freq);
    
    f0 = mean(data_photo_dejit(idx_f0_start : idx_f0_end, i), 'omitnan');
    data_photo_norm_dejit(:, i) = (data_photo_dejit(:, i) - f0) / f0;
end

%% Step 4: Interactive Sweep Review & Exclusion
i = 1;
exclude_sweeps = [];
hFig = figure;

while i <= size(data_photo_norm_dejit, 2)
    clf(hFig);
    if ismember(i, exclude_sweeps)
        plotColor = 'r';
        statusStr = " [EXCLUDED]";
    else
        plotColor = 'k';
        statusStr = " [ACTIVE]";
    end
    
    plot(data_time_dejit, data_photo_norm_dejit(:, i), plotColor);
    grid on;
    title("Photometry Sweep #" + num2str(i) + statusStr, ...
          "[< or ,] Prev | [> or .] Next | [X] Toggle Exclude | [Q] Exit Review");
    
    w = waitforbuttonpress;
    if w == 1
        keyPressed = get(hFig, 'CurrentCharacter');
        switch lower(keyPressed)
            case {',', '<'}
                i = max(1, i - 1);
            case {'.', '>'}
                i = min(size(data_photo_norm_dejit, 2), i + 1);
            case 'x'
                if ismember(i, exclude_sweeps)
                    exclude_sweeps(exclude_sweeps == i) = [];
                else
                    exclude_sweeps = [exclude_sweeps, i];
                end
            case 'q'
                break;
        end
    end
end
close(hFig);

% Apply sweep exclusions by setting excluded columns to NaN
for i = 1 : size(data_photo_norm_dejit, 2)
    if ismember(i, exclude_sweeps)
        data_photo_norm_dejit(:, i) = NaN;
    end
end

%% Step 5: Calculate Mean of Included Sweeps
mean_data_photo_norm_dejit = mean(data_photo_norm_dejit, 2, "omitnan");

%% Step 6: Down-Sample to Target Frequency (red_freq)
ds_factor = round(acq_freq / red_freq);
nBins = floor(length(data_time_dejit) / ds_factor);

data_time_red = zeros(nBins, 1);
mean_data_photo_red = zeros(nBins, 1);

for i = 1 : nBins
    idx_range = (i - 1) * ds_factor + 1 : i * ds_factor;
    data_time_red(i) = mean(data_time_dejit(idx_range), 'omitnan');
    mean_data_photo_red(i) = mean(mean_data_photo_norm_dejit(idx_range), 'omitnan');
end

output_data = [data_time_red, mean_data_photo_red];

% Plot Final Averaged Trace
figure;
plot(output_data(:, 1), output_data(:, 2), 'b-', 'LineWidth', 1.5);
xlabel('Time (s)');
ylabel('\DeltaF/F_0');
title('Averaged Normalized DeJittered Photometry Data');
grid on;

%% Step 7: Peak Kinetics Analysis
baseline_win = [max(photo_start + 50, stim_start - 200), stim_start]; % ms window prior to stim

% Passes stim_start (ms) to subtract stimulus delay from peak latencies
peak_results = analyze_photometry_peak(output_data(:, 1), output_data(:, 2), baseline_win, red_freq, stim_start);

% Display analysis summary in Tab-Separated Columns (Excel friendly)
fprintf('\n--- PEAK KINETICS ANALYSIS DATA TABLE ---\n');
fprintf('Direction\tAmplitude (dF/F0)\tPeak Time rel Stim (s)\tTime to 10%% rel Stim (s)\tRise Time 10-90%% (s)\tHalf-Width (s)\tDecay Time 50%% (s)\n');
fprintf('%s\t%.6f\t%.6f\t%.6f\t%.6f\t%.6f\t%.6f\n', ...
        peak_results.peak_dir, ...
        peak_results.peak_amp, ...
        peak_results.peak_time, ...
        peak_results.time_to_10, ...
        peak_results.rise_time_10_90, ...
        peak_results.half_width, ...
        peak_results.decay_time_50);
fprintf('-----------------------------------------\n');


%% Local Analysis Function
function metrics = analyze_photometry_peak(time_vec, signal_vec, baseline_window_ms, sampling_freq, stim_start_ms)
% ANALYZE_PHOTOMETRY_PEAK Calculates kinetics and peak metrics safely with NaNs.

    stim_start_sec = stim_start_ms / 1000;

    % Baseline calculation
    base_samples = max(1, round(baseline_window_ms(1) / 1000 * sampling_freq)) : ...
                   min(length(signal_vec), round(baseline_window_ms(2) / 1000 * sampling_freq));
               
    base_data = signal_vec(base_samples);
    valid_base = base_data(~isnan(base_data));
    
    if isempty(valid_base)
        warning('Baseline window contained only NaNs. Using first non-NaN value as baseline.');
        baseline_val = signal_vec(find(~isnan(signal_vec), 1, 'first'));
    else
        baseline_val = mean(valid_base);
    end
    
    sig_base_sub = signal_vec - baseline_val;
    
    nan_mask = isnan(sig_base_sub) | isnan(time_vec);
    clean_sig  = sig_base_sub(~nan_mask);
    clean_time = time_vec(~nan_mask);
    
    if isempty(clean_sig)
        error('Entire signal trace is NaN. Check your mask and baseline windows.');
    end

    [max_pos, idx_max_pos] = max(clean_sig);
    [max_neg, idx_max_neg] = min(clean_sig);
    
    if abs(max_pos) >= abs(max_neg)
        peak_dir = 'positive';
        peak_amp_raw = max_pos;
        idx_peak = idx_max_pos;
        norm_sig = clean_sig / max_pos;
    else
        peak_dir = 'negative';
        peak_amp_raw = max_neg;
        idx_peak = idx_max_neg;
        norm_sig = clean_sig / max_neg;
    end
    
    abs_peak_time = clean_time(idx_peak);
    
    % --- ENFORCE POST-STIMULUS ONSET SEARCH ---
    % Find index corresponding to stim_start in the cleaned time vector
    idx_stim = find(clean_time >= stim_start_sec, 1, 'first');
    if isempty(idx_stim) || idx_stim >= idx_peak
        idx_stim = 1; % Fallback if stim_start is missing or after peak
    end

    % Rise phase bounded strictly from stim_start to peak
    rise_phase = norm_sig(idx_stim:idx_peak);
    time_rise  = clean_time(idx_stim:idx_peak);
    
    % Search for 10% and 90% threshold crossings within post-stimulus rise phase
    rel_idx_10 = find(rise_phase >= 0.1, 1, 'first');
    rel_idx_90 = find(rise_phase >= 0.9, 1, 'first');
    
    if ~isempty(rel_idx_10) && rel_idx_10 > 1
        x_pts = rise_phase(rel_idx_10-1 : rel_idx_10);
        y_pts = time_rise(rel_idx_10-1 : rel_idx_10);
        if x_pts(1) == x_pts(2)
            abs_t_10 = y_pts(2);
        else
            abs_t_10 = interp1(x_pts, y_pts, 0.1);
        end
    elseif ~isempty(rel_idx_10)
        abs_t_10 = time_rise(rel_idx_10);
    else
        abs_t_10 = clean_time(idx_stim); % Default to stim_start if no threshold found
    end
    
    if ~isempty(rel_idx_90) && rel_idx_90 > 1
        x_pts = rise_phase(rel_idx_90-1 : rel_idx_90);
        y_pts = time_rise(rel_idx_90-1 : rel_idx_90);
        if x_pts(1) == x_pts(2)
            abs_t_90 = y_pts(2);
        else
            abs_t_90 = interp1(x_pts, y_pts, 0.9);
        end
    elseif ~isempty(rel_idx_90)
        abs_t_90 = time_rise(rel_idx_90);
    else
        abs_t_90 = abs_peak_time;
    end
    
    % Calculate relative times (guaranteed >= 0)
    peak_time_rel  = abs_peak_time - stim_start_sec;
    time_to_10_rel = max(0, abs_t_10 - stim_start_sec); 
    
    rise_time_10_90 = abs_t_90 - abs_t_10;
    
    % 50% Rise Time for Half-Width calculation
    rel_idx_50_rise = find(rise_phase >= 0.5, 1, 'first');
    if ~isempty(rel_idx_50_rise) && rel_idx_50_rise > 1
        x_pts = rise_phase(rel_idx_50_rise-1 : rel_idx_50_rise);
        y_pts = time_rise(rel_idx_50_rise-1 : rel_idx_50_rise);
        if x_pts(1) == x_pts(2)
            t_50_rise = y_pts(2);
        else
            t_50_rise = interp1(x_pts, y_pts, 0.5);
        end
    else
        t_50_rise = NaN;
    end
    
    % Decay Phase Calculation
    decay_phase = norm_sig(idx_peak:end);
    time_decay  = clean_time(idx_peak:end);
    
    idx_50_decay = find(decay_phase <= 0.5, 1, 'first');
    if ~isempty(idx_50_decay) && idx_50_decay > 1
        x_pts = decay_phase(idx_50_decay-1 : idx_50_decay);
        y_pts = time_decay(idx_50_decay-1 : idx_50_decay);
        if x_pts(1) == x_pts(2)
            t_50_decay = y_pts(1);
        else
            t_50_decay = interp1(x_pts, y_pts, 0.5);
        end
    elseif ~isempty(idx_50_decay)
        t_50_decay = time_decay(idx_50_decay);
    else
        t_50_decay = NaN;
    end
    
    half_width    = t_50_decay - t_50_rise;
    decay_time_50 = t_50_decay - abs_peak_time;
    
    % Return struct
    metrics = struct();
    metrics.peak_amp        = peak_amp_raw;
    metrics.peak_dir        = peak_dir;
    metrics.peak_time       = peak_time_rel;  % Relative to stim_start (s)
    metrics.time_to_10      = time_to_10_rel; % Relative to stim_start (s), >= 0
    metrics.rise_time_10_90 = rise_time_10_90;
    metrics.half_width      = half_width;
    metrics.decay_time_50   = decay_time_50;
end