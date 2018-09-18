function [aap, resp] = aamod_seedConnectivity(aap, task, subj)

resp = '';


switch task
    case 'report'
        
    case 'doit'
        
%         if ~(marsbar('is_started'))
%             marsbar on;
%         end

        settings = aap.tasklist.currenttask.settings;
        
        % Subject name and directory
        subjDir = aas_getsubjpath(aap, subj);
        
        % Load the SPM model
        SPM = load(aas_getfiles_bystream(aap, subj, 'firstlevel_spm'));
        SPM = SPM.SPM;
        
        % path to the mask.nii generated by SPM model
        brainMaskDir = SPM.swd;
        
        % Misc image information... (using first image as a template)
        imgDim = SPM.xY.VY(1).dim;         % Dimensions of the images
        imgMat = SPM.xY.VY(1).mat;         % Orientation, scaling, etc.
        
        % aap.directory_conventions.stats_singlesubj
        % can have module specific value, but kept for backwards
        % compatability
        if (isfield(aap.tasklist.currenttask.extraparameters,'stats_suffix'))
            stats_suffix=aap.tasklist.currenttask.extraparameters.stats_suffix;
        else
            stats_suffix=[];
        end
        
        anaDir = fullfile(subjDir, [aap.directory_conventions.stats_singlesubj stats_suffix]);
        if ~exist(anaDir,'dir')
            mkdir(subjDir, [aap.directory_conventions.stats_singlesubj stats_suffix]);
        end
        cd(anaDir);
        
        if any(strcmp('rois', aap.tasklist.currenttask.inputstreams.stream))
            
            roiFiles = aas_getfiles_bystream(aap, subj, 'rois');
            seedROIV = spm_vol(roiFiles(settings.seedROIindex, :));
            
            if ~spm_check_orientations([seedROIV SPM.xY.VY(1)]), aas_log(aap,true,'Image orientation mismatch. has input stream ''rois'' been resliced to your EPI space?'); end
            
            [Yroi roiXYZ] = spm_read_vols(seedROIV);
            roiVoxI = find(Yroi(:));
%             roiXYZ = roiXYZ(:, roiVoxI);
            [x y z] = ind2sub(seedROIV.dim, roiVoxI);
            
            roiXYZ = [x'; y'; z'];
            
            [path fcDesc ext] = fileparts(roiFiles(settings.seedROIindex, :));

        else
            
            % ROI description
            roiDesc = aap.tasklist.currenttask.settings.ROIdesc;
            roiRadius = aap.tasklist.currenttask.settings.radius;
            
            % Get the ROI description for this subject
            subjI = [];
            for r = 1 : length(roiDesc)
                if ischar(roiDesc(r).subject)
                    if strcmp(roiDesc(r).subject, '*') || strcmp(roiDesc(r).subject, aap.acq_details.subjects(subj).subjname)
                        subjI = r;
                        break;
                    end
                else
                    if roiDesc(r).subject == subj
                        subjI = r;
                        break;
                    end
                end
            end
            
            if isempty(subjI), aas_log(aap,true,'No ROI description found for this subject!'); end
            
            roiDesc = roiDesc(subjI).roi;

            % TODO: verify coordinates (3 numbers, within the volume, etc).
            fcDesc = sprintf('%d_%d_%d_r=%d', roiDesc(1), roiDesc(2), roiDesc(3), roiRadius);
            seed = maroi_sphere(struct('centre', roiDesc, 'radius', roiRadius));
            
            %             % Save an image of the ROI, used for masking the analysis
            %             if vargs.mask
            %                 roi1F = sprintf('Sphere_$d_%d_%D.img', roi1Name(i,1), roi1Name(i,2), roi1Name(i,3));
            %                 roi1F = fullfile(rDir, roi1F);
            %                 save_as_image(roi1, fullfile(roi1, 'RL.img'));
            %             end

            roiXYZ = voxpts(seed, struct('mat', imgMat, 'dim', imgDim));
            roiXYZ = [roiXYZ; ones(1, size(roiXYZ,2))];
            roiVoxI = sub2ind(imgDim, roiXYZ(1,:), roiXYZ(2,:), roiXYZ(3,:)); 
        end

        % Extract the seed data
        y = spm_get_data(SPM.xY.VY, roiXYZ);
        
        % Correct seed time series for confounds (entire design matrix)? NOT YET TESTED
        if aap.tasklist.currenttask.settings.correctSeed
%                         Better way to get residuals, but model migh tnot
%                         be estimated yet...
%             KWY = spm_filter(SPM.xX.K, SPM.xX.W*Y); % Whiten and filter the data...
%             Y = spm_sp('r', SPM.xX.xKXs, KWY);      % Calculate residuals...
%             clear KWY; % save memory
            
            X = spm_sp('Set', SPM.xX.X);
            y = spm_sp('res', X, y);
        end
        y = y(:,~any(isnan(y)));
        
        % Summarize the seed voxels' time series into a single timecourse
        switch aap.tasklist.currenttask.settings.summaryFun
            
            case 'mean'
                Y = mean(y, 2);
                
            case 'median'
                Y = median(y, 2);
                
            case 'eigen1'
                [m n]   = size(y);
                if m > n
                    [v s v] = svd(spm_atranspa(y));
                    s       = diag(s);
                    v       = v(:,1);
                    u       = y*v/sqrt(s(1));
                else
                    [u s u] = svd(spm_atranspa(y'));
                    s       = diag(s);
                    u       = u(:,1);
                    v       = y'*u/sqrt(s(1));
                end
                d       = sign(sum(v));
                u       = u*d;
                v       = v*d;
                Y       = u*sqrt(s(1)/n);
                
            case 'default'
                aas_log(aap, 1, 'Invalid summary function option');
        end
        

        % Copy settings from the original SPM model
        fcSPM.xY.P = SPM.xY.P;
        fcSPM.xBF = SPM.xBF;
        fcSPM.xY.RT = SPM.xY.RT;
        fcSPM.nscan = SPM.nscan;
        fcSPM.xGX.iGXcalc = SPM.xGX.iGXcalc;
        fcSPM.xVi.form = SPM.xVi.form;
        
        % Copy Session Info
        nScans = cumsum([0 fcSPM.nscan]);
        iC = []; iG = [];
        
        nPrevCols = 0;
        for sess = 1 : length(SPM.Sess)
            
            fcSPM.xX.K(sess).HParam = SPM.xX.K(sess).HParam;
            
            % Indices of scans in this session
            vI = nScans(sess)+1 : nScans(sess+1);
            
            % Add in the seed time series
            fcSPM.Sess(sess).C.C = [Y(vI) SPM.Sess(sess).C.C];
            fcSPM.Sess(sess).C.name = ['seed' SPM.Sess(sess).C.name];
            
            % Copy Events, if present
            if ~isempty(SPM.Sess(sess).U)
                for k = 1 : length(SPM.Sess(sess).U)
                    fcSPM.Sess(sess).U(k) = struct(            ...
                        'ons',     SPM.Sess(sess).U(k).ons,    ...
                        'dur',     SPM.Sess(sess).U(k).dur,    ...
                        'name',    {SPM.Sess(sess).U(k).name}, ...
                        'P',       SPM.Sess(sess).U(k).P);
                end
                nPrevCols = nPrevCols + length(SPM.Sess(sess).U);
            else
                fcSPM.Sess(sess).U = {};
            end
            
            % Only the seed time series is a column of interest
            iC = [iC nPrevCols+1];
            iG = [iG nPrevCols+2:size(fcSPM.Sess(sess).C.C, 2)];
            nPrevCols = nPrevCols + size(fcSPM.Sess(sess).C.C, 2);   
        end
        
        % Configure design matrix
        fcSPM = spm_fmri_spm_ui(fcSPM);
        
        fcSPM.xX.iC = iC;
        fcSPM.xX.iG = iG;
        
        % Mask the analysis with the ROI file, nice!
        mask = ones(imgDim);
        mask(roiVoxI) = 0;
        maskV = SPM.xY.VY(1);
        maskV.fname = fullfile(anaDir, 'NOT_roi.nii');
        spm_write_vol(maskV, mask);
        fcSPM.xM.VM = spm_vol(maskV.fname);
        fcSPM.xM.xs.Masking = 'analysis threshold+explicit mask';
        
        fcSPM.xX.X = double(fcSPM.xX.X);
        
        % Estimate parameters
        spm_unlink(fullfile('.', 'mask.img')); % avoid overwrite dialog
        fcSPM = spm_spm(fcSPM);
        
        % Create a t-contrast for the seed time series
        seedContrast = zeros(1, size(fcSPM.xX.X, 2));
        seedContrast(iC) = 1;
        fcSPM.xCon =  spm_FcUtil('Set', fcDesc, 'T', 'c', seedContrast', fcSPM.xX.xKXs);
        spm_contrasts(fcSPM);
        

end

end
