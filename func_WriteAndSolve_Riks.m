function func_WriteAndSolve_Riks(Nodes_imperfect, Elements_3D, Stress_Matrix, bottom_nodes, top_nodes, L, E, nu, jobName)
% FUNC_WRITEANDSOLVE_RIKS 生成带残余应力和初始缺陷的 Riks 模型并静默求解
% 
% 核心逻辑：
% 1. NSET 强制解耦：端部节点 ID 直接传入，彻底规避缺陷坐标漂移导致的容差抓取失败。
% 2. 初始状态：通过 *Initial Conditions 读入三维残余应力全局矩阵。
% 3. 极值控制：采用考虑大变形 (nlgeom=YES) 的位移控制 Riks 弧长法。
% 4. 性能优化：调用多核并行求解加速计算。

    % --- 1. 参考点定义 ---
    max_node_id = max(Nodes_imperfect(:, 1));
    rp_bottom_id = max_node_id + 1;
    rp_top_id    = max_node_id + 2;
    
    % --- 2. 编写 .inp 文件 ---
    inp_filename = [jobName, '.inp'];
    fid = fopen(inp_filename, 'w');
    if fid == -1
        error('[Error] 无法创建或打开 INP 文件。');
    end
    
    fprintf(fid, '*Heading\n');
    fprintf(fid, '** Job name: %s\n', jobName);
    fprintf(fid, '*Preprint, echo=NO, model=NO, history=NO, contact=NO\n');
    
    % (1) 实体节点写入 (带有几何初始缺陷的 Nodes_imperfect)
    fprintf(fid, '*Node\n');
    fprintf(fid, '%d, %.6f, %.6f, %.6f\n', Nodes_imperfect');
    
    % (2) 刚性参考点 (Reference Points)
    fprintf(fid, '** Reference Points\n');
    fprintf(fid, '%d, 0.0, 0.0, 0.0\n', rp_bottom_id);
    fprintf(fid, '%d, 0.0, 0.0, %.6f\n', rp_top_id, L);
    
    % (3) 单元拓扑写入 (C3D8R)
    fprintf(fid, '*Element, type=C3D8R, elset=All_Elements\n');
    fprintf(fid, '%d, %d, %d, %d, %d, %d, %d, %d, %d\n', Elements_3D');
    
    % (4) 定义节点集 (严格应用 16 项换行限制，直接使用传入的纯净 ID)
    % 写入 Bottom_Nodes
    fprintf(fid, '*Nset, nset=Bottom_Nodes\n');
    for i = 1:length(bottom_nodes)
        if mod(i, 16) == 0 || i == length(bottom_nodes)
            fprintf(fid, '%d\n', bottom_nodes(i));
        else
            fprintf(fid, '%d, ', bottom_nodes(i));
        end
    end
    
    % 写入 Top_Nodes
    fprintf(fid, '*Nset, nset=Top_Nodes\n');
    for i = 1:length(top_nodes)
        if mod(i, 16) == 0 || i == length(top_nodes)
            fprintf(fid, '%d\n', top_nodes(i));
        else
            fprintf(fid, '%d, ', top_nodes(i));
        end
    end
    
    fprintf(fid, '*Nset, nset=RP_Bottom\n');
    fprintf(fid, '%d\n', rp_bottom_id);
    
    fprintf(fid, '*Nset, nset=RP_Top\n');
    fprintf(fid, '%d\n', rp_top_id);
    
    % (5) 表面与运动学耦合 (Kinematic Coupling)
    fprintf(fid, '** Define node-based surfaces for coupling\n');
    fprintf(fid, '*Surface, type=NODE, name=Bottom_Surf\n');
    fprintf(fid, 'Bottom_Nodes, 1.0\n');
    fprintf(fid, '*Surface, type=NODE, name=Top_Surf\n');
    fprintf(fid, 'Top_Nodes, 1.0\n');
    
    fprintf(fid, '** Kinematic Coupling\n');
    fprintf(fid, '*Coupling, constraint name=Coupling-Bottom, ref node=RP_Bottom, surface=Bottom_Surf\n');
    fprintf(fid, '*Kinematic\n');
    fprintf(fid, '1, 6\n');
    
    fprintf(fid, '*Coupling, constraint name=Coupling-Top, ref node=RP_Top, surface=Top_Surf\n');
    fprintf(fid, '*Kinematic\n');
    fprintf(fid, '1, 6\n');
    
    % (6) 材料与截面属性 (理想弹塑性)
    fprintf(fid, '*Solid Section, elset=All_Elements, material=Steel\n');
    fprintf(fid, ',\n');
    fprintf(fid, '*Material, name=Steel\n');
    fprintf(fid, '*Elastic\n');
    fprintf(fid, '%.2f, %.3f\n', E, nu);
    fprintf(fid, '*Plastic\n');
    fprintf(fid, '355.0, 0.0\n');
    
    % (7) 引入残余应力场 (Initial Conditions 缝合)
    fprintf(fid, '** Residual Stress Initialization\n');
    fprintf(fid, '*Initial Conditions, type=STRESS\n');
    % Stress_Matrix 格式: [ElemID, S11, S22, S33, S12, S13, S23]
    fprintf(fid, '%d, %.4f, %.4f, %.4f, %.4f, %.4f, %.4f\n', Stress_Matrix');
    
    % --- 3. 分析步与载荷边界 (Riks 位移控制) ---
    fprintf(fid, '*Step, name=Riks_Step, nlgeom=YES, inc=200\n');
    % Riks 参数: 初始弧长 0.001, 估计总弧长 1.0, 最小弧长 0.001, 最大弧长 0.01
    fprintf(fid, '*Static, riks\n');
    fprintf(fid, '0.001, 1.0, 0.001, 0.01\n'); 
    
    fprintf(fid, '*Boundary\n');
    % 底部两端铰接边界 (释放主/弱轴转动)
    fprintf(fid, 'RP_Bottom, 1, 3\n');
    fprintf(fid, 'RP_Bottom, 6, 6\n');
    fprintf(fid, 'RP_Top, 1, 2\n');
    fprintf(fid, 'RP_Top, 6, 6\n');
    
    % 顶部施加 Z 向位移荷载 (-100)
    fprintf(fid, 'RP_Top, 3, 3, -100.0\n');
    
    % --- 4. 场输出与历史数据请求 ---
    fprintf(fid, '*Output, field\n');
    fprintf(fid, '*Node Output\n');
    fprintf(fid, 'U, RF\n');
    fprintf(fid, '*Element Output\n');
    fprintf(fid, 'S, LE, PE\n');
    
    % [极度关键]: 将顶部 RP 的位移和反力直接打印到 .dat 文件
    fprintf(fid, '*Node Print, nset=RP_Top, freq=1, summary=NO, total=NO\n');
    fprintf(fid, 'U3, RF3\n');
    
    fprintf(fid, '*End Step\n');
    fclose(fid);
    
    % --- 5. 后台静默求解 (多核加速) ---
    num_cpus = 8; % 设定调用的 CPU 核心数
    disp(['[Solve B] 正在提交 Riks 非线性求解 (多核加速: ', num2str(num_cpus), '核) : ', jobName, ' ...']);
    
    % 在命令字符串中加入 cpus 参数
    cmd = sprintf('abaqus job=%s cpus=%d interactive ask_delete=OFF', jobName, num_cpus);
    status = system(cmd);
    
    if status == 0
        disp('[Solve B] Riks 求解完成，.dat 及 .odb 结果已生成。');
    else
        error('[Solve B] Abaqus 求解失败，请检查 .msg 或 .dat 文件定位发散或报错原因。');
    end

end