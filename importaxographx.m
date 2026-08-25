% Import AxoGraph X files into MATLAB
% https://github.com/CWRUChielLab/importaxographx
%
% This script is provided with AxoGraph X and has been modified to correct a few problems.
% Corrections by: Jeffrey Gill <jeffrey.p.gill@gmail.com>

function [data, hd] = importaxographx(fn)
%IMPORTAXOGRAPHX Import Axograph files
%   [data, hd] = importaxographx(filename)
%   [data, hd] = importaxographx(folderPath) -> opens dialog box in specified folder
%   [data, hd] = importaxographx -> opens a dialog box in default folder
%
%   Imports Axograph files into MATLAB. <filename> can be a string, cell
%   array of strings, or a directory path string. <data> will be a 2-D double array,
%   <time, column>, or a 3-D double array when importing several files at once: 
%   <time, column, filenumber>. When importing several files at once, data must
%   have the same size.

    % Default fallback path if no folder/file is specified
    defaultFolder = '/Volumes/ANDREW_DATA/2026/Data/08_August/';

    % Check if input argument is missing OR if input is a directory folder path
    if nargin < 1 || (ischar(fn) || isstring(fn)) && isfolder(fn)
        if nargin >= 1 && isfolder(fn)
            targetPath = fullfile(fn, '*.*');
        else
            targetPath = fullfile(defaultFolder, '*.*');
        end
        
        [fn, pn] = uigetfile('*.*', 'Pick an Axograph file', targetPath, 'MultiSelect', 'on');
        
        % Handle user cancel in file dialog
        if isequal(fn, 0) || isequal(pn, 0)
            data = []; hd = [];
            disp('Import cancelled by user.');
            return;
        end
    else
        pn = '';
    end

    % Standardize single file selection string to cell array for loop compatibility
    if ~iscell(fn)
        fn = {fn};
    end

    for iFn = 1:length(fn)
        fprintf(1, ['importing from ', fn{iFn}, '... '])
        [data(:,:,iFn), hd(iFn)] = importFromFile(fullfile(pn, fn{iFn}));
        fprintf(1, 'done\n')
    end
end
function [data, hd] = importFromFile(fn)
%subfunction which does the actual job. For Axograph file header details
%see the Axograph 4.6 User Manual or Neuromatica's ReadAxograph import filter

    fid = fopen(fn, 'r', 'b');

    hd.nameOnDisk   = fn;
    hd.OSType       = fread(fid, 4, '*char')';
    hd.fileFormat   = fread(fid, 1, 'int32')';
    hd.nDatCol      = fread(fid, 1, 'int32')';

    for iYCol = 1:(hd.nDatCol)
        hd.YCol(iYCol).nPoints  = fread(fid, 1, 'int32')';
        hd.YCol(iYCol).colType = fread(fid, 1, 'int32')';
        hd.YCol(iYCol).titlelen = fread(fid, 1, 'int32')';
        hd.YCol(iYCol).title    = (fread(fid, hd.YCol(iYCol).titlelen, '*char')');

        %%%%%%%%%%%%%%% REMOVE NULL CHARACTERS %%%%%%%%%%%%%%%
        % It seems that the types are not set correctly for  %
        % the version of AxoGraph X that I have because      %
        % titlelen is double what it should be and title has %
        % null characters inserted before each real          %
        % character. This code corrects these errors.        %
        hd.YCol(iYCol).titlelen = hd.YCol(iYCol).titlelen / 2;
        hd.YCol(iYCol).title = hd.YCol(iYCol).title(2:2:end);
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

        switch hd.YCol(iYCol).colType
            case 4  % column type is short
                data(:, iYCol) = double(fread(fid,hd.YCol(iYCol).nPoints, 'int16'));
            case 5  % column type is long
                data(:, iYCol) = double(fread(fid,hd.YCol(iYCol).nPoints, 'int32'));
            case 6  % column type is float
                data(:, iYCol) = double(fread(fid,hd.YCol(iYCol).nPoints, 'float32'));
            case 7  % column type is double
                data(:, iYCol) = fread(fid,hd.YCol(iYCol).nPoints, 'double');
            case 9  % 'series'
                 data0 = fread(fid,2, 'double');
                 %data(:, iYCol) = (1:1:hd.YCol(iYCol).nPoints)*data0(2)+ data0(1);
                 %%%%%%%%%%%%%%%%%%%%%%%% FIX SERIES START %%%%%%%%%%%%%%%%%%%%%%%%%
                 % data0(1) is the starting value, data0(2) is the interval, so    %
                 % the code above is off by one. This code corrects the error.     %
                 data(:, iYCol) = (0:1:hd.YCol(iYCol).nPoints-1)*data0(2)+ data0(1);
                 %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            case 10 % 'scaled short'
                scale = fread(fid,1, 'double');
                offset = fread(fid,1, 'double');
                data0 = fread(fid,hd.YCol(iYCol).nPoints, 'int16');
                data(:, iYCol)  = double(data0)*scale + offset;
            otherwise
                disp(['Unknown column type:' num2str(hd.YCol(iYCol).colType)  ' Cannot continue reading the file']);
        end
    end

end

%fclose(fid);

