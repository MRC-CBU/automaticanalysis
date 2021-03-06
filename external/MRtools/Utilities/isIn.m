function out = isIn(a,b)
%%% is a in b?
%%% Written by Aaron Schultz (aschultz@martinos.org)
%%% Copyright (C) 2014,  Aaron P. Schultz
%%%
%%% Supported in part by the NIH funded Harvard Aging Brain Study (P01AG036694) and NIH R01-AG027435 
%%%
%%% This program is free software: you can redistribute it and/or modify
%%% it under the terms of the GNU General Public License as published by
%%% the Free Software Foundation, either version 3 of the License, or
%%% any later version.
%%% 
%%% This program is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%%% GNU General Public License for more details.

out = [];
if isempty(b);
    out = 0;
    return
else
    if iscell(b)
        for kk = 1:length(b);
            ch = [];
            for ii = 1:length(a);
                ind = find(b{kk}==a(ii));
                if isempty(ind);
                    ind = 0;
                else
                    ind = 1;
                end
                ch(ii) = ind;
            end
            if mean(ch)==1;
                out = kk;
                return;
            end
        end
        if isempty(out)
            out = 0;
            return
        end
    else
        ch = [];
        for ii = 1:length(a);
            ind = find(b==a(ii));
            if isempty(ind);
                ind = 0;
            end
            ch(ii) = ind;  
        end
%         if mean(ch)==1;
%             out = 1;
%         else
%             out = 0;
%         end
        out = ch;
    end
end