function [Nodes_3D, Elements_3D] = func_Extrude2Dto3D(nodes_2d, elems_2d, L, mesh_z)
% FUNC_EXTRUDE2DTO3D 沿Z轴矩阵化拉伸2D网格生成3D网格 (完全消除循环的向量化操作)
%
% 输入参数:
%   nodes_2d: 2D节点矩阵，维度 [N2, 3]，列定义为 [NodeID, X, Y]
%   elems_2d: 2D单元矩阵，维度 [E2, 5]，列定义为 [ElemID, n1, n2, n3, n4]
%   L:        三维构件总长度 (Z向跨度)
%   mesh_z:   Z方向的网格划分尺寸
%
% 输出参数:
%   Nodes_3D: 3D节点矩阵，维度 [N3, 4]，列定义为 [NodeID, X, Y, Z]
%   Elements_3D: 3D单元拓扑矩阵 (C3D8R)，维度 [E3, 9]，列定义为 [ElemID, n1, n2, n3, n4, n5, n6, n7, n8]

    % --- 0. 基础维度与离散参数计算 ---
    num_layers = round(L / mesh_z) + 1;       % Z向节点层数
    num_elem_layers = num_layers - 1;         % Z向单元层数
    z_coords = linspace(0, L, num_layers)';   % Z向实际物理坐标数组
    
    N2 = size(nodes_2d, 1);                   % 截面2D节点总数
    E2 = size(elems_2d, 1);                   % 截面2D单元总数

    % =========================================================
    % 1. 节点空间矩阵化 (Nodes Vectorization)
    % =========================================================
    % 严格遵循层递增规律生成全局节点编号
    NodeIDs_3D = (1:(N2 * num_layers))';

    % 沿Z轴平移：通过 repmat 复制截面坐标 (X, Y)
    X_3D = repmat(nodes_2d(:, 2), num_layers, 1);
    Y_3D = repmat(nodes_2d(:, 3), num_layers, 1);

    % 沿Z轴平移：通过 kronecker 张量积生成阶梯状的 Z 坐标场
    Z_3D = kron(z_coords, ones(N2, 1));

    % 拼接生成最终完美三维节点坐标矩阵
    Nodes_3D = [NodeIDs_3D, X_3D, Y_3D, Z_3D];

    % =========================================================
    % 2. 单元拓扑矩阵化 (Elements Vectorization)
    % =========================================================
    % 严格遵循层递增规律生成全局单元编号
    ElemIDs_3D = (1:(E2 * num_elem_layers))';

    % 提取2D网格的拓扑关系 (基准面节点编号)
    base_conn = elems_2d(:, 2:5);

    % 计算各Z向单元层对应基准面节点的索引偏移矩阵 (0, N2, 2*N2, ...)
    layer_offsets = (0:(num_elem_layers - 1))' * N2;
    offset_matrix = kron(layer_offsets, ones(E2, 1));

    % 并行生成三维实体单元的底面和顶面节点编号
    conn_bottom = repmat(base_conn, num_elem_layers, 1) + offset_matrix;
    conn_top    = conn_bottom + N2;

    % 拼接生成最终 C3D8R 单元拓扑矩阵 (底层1-2-3-4，顶层5-6-7-8)
    Elements_3D = [ElemIDs_3D, conn_bottom, conn_top];

end