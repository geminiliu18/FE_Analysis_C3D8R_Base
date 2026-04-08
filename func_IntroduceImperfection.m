function Nodes_imperfect = func_IntroduceImperfection(Nodes_perfect, dat_filename, scale_factor)
% FUNC_INTRODUCEIMPERFECTION 从 Buckle 的 .dat 文件提取一阶模态位移并叠加几何缺陷
%
% 核心逻辑：完全模拟 Abaqus 中 *IMPERFECTION 关键字的底层数值行为
% 输入参数:
%   Nodes_perfect: 完美三维节点矩阵，维度 [N, 4]，列定义为 [NodeID, X, Y, Z]
%   dat_filename:  Buckle 求解生成的 .dat 文件路径 (例如 'Job_Buckle.dat')
%   scale_factor:  缩放系数 (例如 3.0，对应 *IMPERFECTION 命令中的数值)
% 输出参数:
%   Nodes_imperfect: 引入缺陷后的节点矩阵，维度 [N, 4]

    % --- 0. 初始化与预分配 ---
    num_nodes = size(Nodes_perfect, 1);
    Nodes_imperfect = Nodes_perfect; % 初始化为完美坐标
    
    % 预分配提取矩阵，提升读取效率 [ID, U1, U2, U3]
    extracted_data = zeros(num_nodes, 4); 
    count = 0;

    % --- 1. 打开 .dat 文件 ---
    fid = fopen(dat_filename, 'r');
    if fid == -1
        error('[Error] 无法打开文件: %s，请检查求解是否成功以及文件路径。', dat_filename);
    end

    % --- 2. 文本解析：定位并提取节点位移 ---
    in_data_block = false;

    while ~feof(fid)
        line = strtrim(fgetl(fid));
        
        % 寻找一阶模态的节点输出表头 (Abaqus .dat 标准输出格式)
        % 关键字：通常包含 NODE FOOT- 以及 U1 U2 U3
        if contains(line, 'NODE FOOT-') && contains(line, 'U1') && contains(line, 'U2')
            in_data_block = true;
            continue;
        end
        
        if in_data_block
            % 遇到 MAXIMUM 或 MINIMUM 统计信息，说明当前模态数据区结束
            if startsWith(line, 'MAXIMUM') || startsWith(line, 'MINIMUM')
                break; % 停止读取，我们只需要一阶模态（最先出现的）
            end
            
            % 跳过空行或 Abaqus 的分页头
            if isempty(line) || contains(line, 'PAGE', 'IgnoreCase', true) || contains(line, 'THE FOLLOWING TABLE')
                continue;
            end
            
            % 尝试解析数据行 (Abaqus 数据行以节点号即数字开头)
            if isstrprop(line(1), 'digit')
                data = sscanf(line, '%f');
                % 确保解析出了至少 4 个数据：ID, U1, U2, U3
                if length(data) >= 4
                    count = count + 1;
                    % 动态扩容以防 dat 文件包含额外节点（如 Reference Points）
                    if count > size(extracted_data, 1)
                        extracted_data = [extracted_data; zeros(1000, 4)]; %#ok<AGROW>
                    end
                    extracted_data(count, 1:4) = data(1:4)';
                end
            end
        end
    end
    fclose(fid);
    
    % 截断未使用的预分配空间
    extracted_data = extracted_data(1:count, :);

    if count == 0
        error('[Error] 未能在 .dat 文件中读取到有效的位移数据，请检查 *NODE PRINT 输出设置。');
    end

    % --- 3. 矩阵映射与向量化叠加 ---
    % 利用 ismember 建立 dat 文件中的 ID 与全局 Nodes_perfect 矩阵行的映射关系
    % 这种方法即使 dat 文件中由于 NSET 的原因漏掉了某些节点，或者顺序打乱，也能完美对应
    [lia, loc] = ismember(extracted_data(:, 1), Nodes_perfect(:, 1));
    
    % lia 表示 extracted_data 的节点在 Nodes_perfect 中是否存在 (逻辑数组)
    % loc 表示 extracted_data 的节点在 Nodes_perfect 中的行号
    
    valid_extracted_idx = lia;               % dat 中有效数据的行索引
    target_node_rows = loc(valid_extracted_idx); % 对应的 Nodes_perfect 行索引
    
    % 核心计算：坐标叠加 (严格等价于 *IMPERFECTION, 1, 3.0)
    % X_new = X_old + scale_factor * U1
    Nodes_imperfect(target_node_rows, 2:4) = Nodes_perfect(target_node_rows, 2:4) + scale_factor * extracted_data(valid_extracted_idx, 2:4);

    disp(['[Solve A 解析] 成功提取一阶模态，已完成几何初始缺陷叠加。缩放系数: ', num2str(scale_factor)]);

end