function Stress_Matrix = func_GenerateStressField(nodes_2d, elems_2d, num_elem_layers, fy)
% FUNC_GENERATESTRESSFIELD 基于 2D 截面生成 3D 构件的残余应力场 (Abaqus 初始应力格式)
%
% 输入参数:
%   nodes_2d: 2D节点矩阵 [NodeID, X, Y]
%   elems_2d: 2D单元矩阵 [ElemID, n1, n2, n3, n4]
%   num_elem_layers: Z向三维单元的总层数
%   fy: 钢材屈服强度 (例如 355.0)
%
% 输出参数:
%   Stress_Matrix: 全局三维残余应力矩阵 [ElemID3D, S11, S22, S33, S12, S13, S23]

    % --- 0. 提取 2D 单元形心坐标 ---
    X_nodes = nodes_2d(:, 2);
    Y_nodes = nodes_2d(:, 3);
    
    n1 = elems_2d(:, 2); n2 = elems_2d(:, 3); 
    n3 = elems_2d(:, 4); n4 = elems_2d(:, 5);
    
    Xc = (X_nodes(n1) + X_nodes(n2) + X_nodes(n3) + X_nodes(n4)) / 4;
    Yc = (Y_nodes(n1) + Y_nodes(n2) + Y_nodes(n3) + Y_nodes(n4)) / 4;
    
    num_elems_2d = size(elems_2d, 1);
    
    % --- 1. 自动化提取截面几何特征 (H, B, tf, tw) ---
    Y_max = max(Y_nodes); Y_min = min(Y_nodes); 
    H = Y_max - Y_min;    Y0 = (Y_max + Y_min) / 2;
    
    X_max = max(X_nodes); X_min = min(X_nodes); 
    B = X_max - X_min;    X0 = (X_max + X_min) / 2;
    
    % 通过形心分布提取翼缘和腹板厚度
    % 提取腹板厚度 (取 Y 接近形心位置的单元)
    idx_mid = abs(Yc - Y0) < (0.1 * H);
    tw = max(X_nodes(elems_2d(idx_mid, 2:5)), [], 'all') - min(X_nodes(elems_2d(idx_mid, 2:5)), [], 'all');
    
    % 提取翼缘厚度 (取 X 坐标跨度较大的区域)
    uniq_Y = uniquetol(Y_nodes, 1e-4);
    widths = zeros(length(uniq_Y), 1);
    for i = 1:length(uniq_Y)
        widths(i) = max(X_nodes(abs(Y_nodes - uniq_Y(i)) < 1e-4)) - min(X_nodes(abs(Y_nodes - uniq_Y(i)) < 1e-4));
    end
    top_flange_Y = uniq_Y(uniq_Y > Y0 & widths > 0.5 * B);
    tf = max(top_flange_Y) - min(top_flange_Y);

    % --- 2. 单元分区索引划分 ---
    idx_top_flange = Yc > (Y_max - tf - 1e-4);
    idx_bot_flange = Yc < (Y_min + tf + 1e-4);
    idx_web = (~idx_top_flange) & (~idx_bot_flange);

    % --- 3. 定义 ECCS 分布幅值 (中间层基准) ---
    % 严格遵循自平衡抛物线模型
    sigma_rc = -0.30 * fy;    % 翼缘尖端 (受压)
    sigma_rt =  0.15 * fy;    % 翼缘中部 (受拉) -> 保证抛物线积分平衡
    sigma_wt =  0.15 * fy;    % 腹板两端 (受拉)
    sigma_wc = -0.075 * fy;   % 腹板中部 (受压) -> 保证抛物线积分平衡

    S33_base = zeros(num_elems_2d, 1);

    % 3.1 翼缘基准应力 (抛物线分布: 尖端受压，中部受拉)
    xi_f_top = abs(Xc(idx_top_flange) - X0) / (B / 2);
    S33_base(idx_top_flange) = sigma_rt + (sigma_rc - sigma_rt) * (xi_f_top.^2);
    
    xi_f_bot = abs(Xc(idx_bot_flange) - X0) / (B / 2);
    S33_base(idx_bot_flange) = sigma_rt + (sigma_rc - sigma_rt) * (xi_f_bot.^2);

    % 3.2 腹板基准应力 (抛物线分布: 两端受拉，中部受压)
    hw = H - 2 * tf;
    xi_w = abs(Yc(idx_web) - Y0) / (hw / 2);
    S33_base(idx_web) = sigma_wc + (sigma_wt - sigma_wc) * (xi_w.^2);

    % --- 4. 自适应层数检测与应力梯度施加 (+/- 10%) ---
    S33_final = S33_base;
    
    % 4.1 上翼缘 (自下而上: 0.9 -> 1.1)
    Yc_top = Yc(idx_top_flange);
    unique_Yc_top = sort(uniquetol(Yc_top, 1e-4));
    num_layers_tf = length(unique_Yc_top);
    for i = 1:num_layers_tf
        idx_layer = idx_top_flange & (abs(Yc - unique_Yc_top(i)) < 1e-4);
        multiplier = 0.9 + 0.2 * ((i - 1) / max(1, num_layers_tf - 1)); 
        S33_final(idx_layer) = S33_base(idx_layer) * multiplier;
    end

    % 4.2 下翼缘 (自上而下: 0.9 -> 1.1)
    Yc_bot = Yc(idx_bot_flange);
    unique_Yc_bot = sort(uniquetol(Yc_bot, 1e-4), 'descend'); % 内侧在上，外侧在下
    num_layers_bf = length(unique_Yc_bot);
    for i = 1:num_layers_bf
        idx_layer = idx_bot_flange & (abs(Yc - unique_Yc_bot(i)) < 1e-4);
        multiplier = 0.9 + 0.2 * ((i - 1) / max(1, num_layers_bf - 1));
        S33_final(idx_layer) = S33_base(idx_layer) * multiplier;
    end

    % 4.3 腹板 (自左向右: 0.9 -> 1.1)
    Xc_web = Xc(idx_web);
    unique_Xc_web = sort(uniquetol(Xc_web, 1e-4));
    num_layers_tw = length(unique_Xc_web);
    for i = 1:num_layers_tw
        idx_layer = idx_web & (abs(Xc - unique_Xc_web(i)) < 1e-4);
        multiplier = 0.9 + 0.2 * ((i - 1) / max(1, num_layers_tw - 1));
        S33_final(idx_layer) = S33_base(idx_layer) * multiplier;
    end

    % --- 5. Z向全矩阵扩展 (沿纵向一致性解耦) ---
    % 将 2D 截面的 S33 复制 num_elem_layers 次
    S33_3D = repmat(S33_final, num_elem_layers, 1);
    
    % 生成其余全 0 的应力分量
    ElemIDs_3D = (1:(num_elems_2d * num_elem_layers))';
    Zero_Col = zeros(size(ElemIDs_3D));

    % 拼接生成 Abaqus *Initial Conditions 需要的矩阵格式
    % 格式: [ElementID, S11, S22, S33, S12, S13, S23]
    Stress_Matrix = [ElemIDs_3D, Zero_Col, Zero_Col, S33_3D, Zero_Col, Zero_Col, Zero_Col];

end