module matrix_mul_2clk#( //8단계의 pipeline register로 구성됨.

)( //정점변환용도로 3x3 행렬곱셈과 평행이동을 계산하는 모듈. DSP 2개를 사용해서 2 클럭마다 정점의 X or Y or Z좌표를 변환함.
    input clk,
    input reset, //synchronous active high reset

    output reg phase, //1비트 플립플롭으로, 이 값이 0일때의 클럭에지에만 vertex 값을 샘플링함. 1일때의 클럭에지에서는 레지스터 값이 유지됨.

    input pipeline_bubble, //이 값이 1이면 버블이 삽입됨. 처음에 submesh_offset이나 행렬성분 불러오기 전에 버블삽입하는 식으로 제어해주면 됨.
    //또한 밑의 vertex_valid가 0으로 들어와도 버블로 취급됨. 

    input signed [15:0] vertex_x, //FIFO에서 꺼낸 정점 좌표들. 보통 2클럭에 한번씩 온다고 생각해야 함.(SQ1.14)
    input signed [15:0] vertex_y, //(SQ1.14)
    input signed [15:0] vertex_z, //(SQ1.14)
    input vertex_valid,

    input signed [15:0] submesh_offset_x, //submesh 정점의 x값에 더해줘서 obj기준 좌표로 변형하기 위한 offset.(SQ7.8)
    input signed [15:0] submesh_offset_y, //서브메쉬 패킷 헤더에서 추출.(SQ7.8)
    input signed [15:0] submesh_offset_z, //(SQ7.8)
    input load_offset, //이 값이 1이면 input으로 들어오는 오프셋 성분을 클럭에지때 레지스터에서 샘플링함.

    input signed [15:0] m_x, //x값에 곱하는 행렬성분 SQ1.14 M = (m00 / m01 / m02) T = (Tx)
    input signed [15:0] m_y, //y값에 곱하는 행렬성분 SQ1.14     (m10 / m11 / m12)     (Ty)
    input signed [15:0] m_z, //z값에 곱하는 행렬성분 SQ1.14     (m20 / m21 / m22)     (Tz)
    input signed [31:0] T, //평행이동 성분.(SQ15.16)
    input load_matrix, //이 값이 1이면 input으로 들어오는 행렬성분을 클럭에지때 레지스터에서 샘플링함.
    
    output reg signed [31:0] cam_out, //변환이 완료된 카메라 기준 좌표(SQ15.16)
    output reg cam_valid

);
wire bubble_insert_comb = pipeline_bubble || (~vertex_valid); //이 값이 1이면 버블을 삽입하게 됨.

reg signed [15:0] offset_x_ff;
reg signed [15:0] offset_y_ff;
reg signed [15:0] offset_z_ff;

reg signed [15:0] m_x_ff;
reg signed [15:0] m_y_ff;
reg signed [15:0] m_z_ff;
reg signed [31:0] T_ff;

// DSP 0: x*m_x + z*m_z
dsp48_mac u_dsp0 (
        .clk        (clk),
        .reset      (reset),
        .clr_accum  (dsp0_clr_accum),
        .load_c     (dsp0_load_c),
        .valid_in   (dsp0_valid_in),
        .a_in       (dsp0_a), //25비트 signed 값
        .b_in       (dsp0_b), //18비트 signed 값
        .c_in       (dsp0_c), //48비트 sigend 값
        .p_out      (dsp0_p), //48비트 sigend 값. output
        .valid_out  (dsp0_valid_out) //output
);
// DSP 1: T + y*m_y
dsp48_mac u_dsp1 (
        .clk        (clk),
        .reset      (reset),
        .clr_accum  (dsp1_clr_accum),
        .load_c     (dsp1_load_c),
        .valid_in   (dsp1_valid_in),
        .a_in       (dsp1_a), //25비트 signed 값
        .b_in       (dsp1_b), //18비트 signed 값
        .c_in       (dsp1_c), //48비트 sigend 값
        .p_out      (dsp1_p), //48비트 sigend 값. output
        .valid_out  (dsp1_valid_out) //output
);

wire dsp0_clr_accum = (st20_step_ff == 1'b0); //(st20_step_ff == 1'b0)일때 이전 결과값을 누산하는것을 방지하고 다음 클럭인 (st20_step_ff == 1'b1)일때 이전 결과값과 누산되게 함.
wire dsp0_load_c = 1'b0; //사용하지 않음.
wire dsp0_valid_in = 1'b0; //사용하지 않음. 값의 유효함은 파이프라인 레지스터의 valid_ff로 판단할 예정.
wire signed [24:0] dsp0_a = (st20_step_ff == 1'b0) ? {{3{st20_obj_x_ff[21]}}, st20_obj_x_ff} : {{3{st20_obj_z_ff[21]}}, st20_obj_z_ff}; //3비트씩 확장. 원본은 22비트
wire signed [17:0] dsp0_b = (st20_step_ff == 1'b0) ? {{2{m_x_ff[15]}}, m_x_ff} : {{2{m_z_ff[15]}}, m_z_ff}; //2비트씩 확장. 원본은 16비트
wire signed [47:0] dsp0_c = 48'b0;
wire signed [47:0] dsp0_p;
wire dsp0_valid_out;

wire dsp1_clr_accum = (st20_step_ff == 1'b0);
wire dsp1_load_c = (st20_step_ff == 1'b0); //(st20_step_ff == 1'b0)일때 T값을 load해야 함.
wire dsp1_valid_in = 1'b0;
wire signed [24:0] dsp1_a = (st20_step_ff == 1'b0) ? 25'b0 : {{3{st20_obj_y_ff[21]}}, st20_obj_y_ff};
wire signed [17:0] dsp1_b = (st20_step_ff == 1'b0) ? 18'b0 : {{2{m_y_ff[15]}}, m_y_ff}; 
wire signed [47:0] dsp1_c = (st20_step_ff == 1'b0) ? {{4{T_ff[31]}}, T_ff, 12'b0} : 48'b0; //y*m_y의 결과값은 SQ8.28이고 T_ff는 SQ15.16이므로 소수점을 맞춰 줘야 함!!!
wire signed [47:0] dsp1_p;
wire dsp1_valid_out;

//stage 1
reg signed [15:0] st10_vertex_x_ff2; //_ff2 붙으면 2클럭에 한번씩 샘플링하는 레지스터임.
reg signed [15:0] st10_vertex_y_ff2;
reg signed [15:0] st10_vertex_z_ff2;
reg st10_valid_ff2; //버블이 들어오면 0을 저장함.

//stage 2
reg signed [21:0] st20_obj_x_ff; //submesh offset 더해서 오브젝트 좌표계로 변환. (SQ7.14)
reg signed [21:0] st20_obj_y_ff; //(SQ7.14)
reg signed [21:0] st20_obj_z_ff; //(SQ7.14)
reg st20_valid_ff;
reg st20_step_ff; //이 값에 따라서 dsp에 보낼 input값이 달라짐. st10에 정상적인 값이 왔다면 두 사이클 값이 유지되므로 처음에 0, 다음에 1 넣어주면 됨.

//stage 3. DSP latency.
reg st30_valid_ff; //st20_valid_ff가 0이고 st20_valid_ff가 1일때만 1을 저장해야 함!!! 그래야 나중에 2클럭에 하나씩 cam_valid가 나옴!!!
//stage 4. DSP latency.
reg st40_valid_ff;
//stage 5. DSP latency.
reg st50_valid_ff;
//stage 6. 누산이 덜 된 p_out이 출력됨. 한 클럭 더 있어야 제대로 된 DSP 0: x*m_x + z*m_z, DSP 1: T + y*m_y이 나옴.
reg st60_valid_ff;

//stage 7. 출력값은 SQ16.28임.
reg signed [47:0] st70_dsp0_p_ff; //x*m_x + z*m_z값은 사실 25bit x 18bit = 43bit이고 누산을 한번 했기때문에 44bit면 충분함. 
reg signed [47:0] st70_dsp1_p_ff; //그런데 T값을 더할때 SQ15.28로 확장했기 때문에 44bit고 누산을 한번하면 45bit까지 갈수 있어서 그냥 p의 출력인 48비트로 통일했음.
reg st70_valid_ff;

//stage 8. output reg인 cam_out과 cam_valid에 값을 넣어주면 됨. 
wire signed [47:0] st80_total_sum_comb = st70_dsp0_p_ff + st70_dsp1_p_ff + 48'sh800; //[11]번비트에 1을 더해주고 [43:12]를 샘플링해서 반올림 함.

//phase 업데이트
always @(posedge clk) begin
    if (reset) begin
        phase <= 1'b0;
    end else begin
        phase <= ~phase; // 0 -> 1 -> 0 -> 1 반복
    end
end

//매 클럭 업데이트되는 플립플롭.
always @(posedge clk) begin
    if(reset) begin
        offset_x_ff <= 0;
        offset_y_ff <= 0;
        offset_z_ff <= 0;

        m_x_ff <= 0;
        m_y_ff <= 0;
        m_z_ff <= 0;
        T_ff <= 0;

        st20_obj_x_ff <= 0;
        st20_obj_y_ff <= 0;
        st20_obj_z_ff <= 0;
        st20_step_ff <= 0;
        st20_valid_ff <= 0;

        st30_valid_ff <= 0;
        st40_valid_ff <= 0;
        st50_valid_ff <= 0;
        st60_valid_ff <= 0;

        st70_dsp0_p_ff <= 0;
        st70_dsp1_p_ff <= 0;
        st70_valid_ff <= 0;

        cam_out <= 0;
        cam_valid <= 0;
    end
    else begin
        if(load_offset) begin //submesh offset load
            offset_x_ff <= submesh_offset_x;
            offset_y_ff <= submesh_offset_y;
            offset_z_ff <= submesh_offset_z;
        end
        if(load_matrix) begin //matrix load
            m_x_ff <= m_x;
            m_y_ff <= m_y;
            m_z_ff <= m_z;
            T_ff <= T;
        end
        //SQ1.14 + SQ7.8이므로 SQ7.14로 확장한 후 더해야 함.
        st20_obj_x_ff <= $signed({{6{st10_vertex_x_ff2[15]}}, st10_vertex_x_ff2}) + $signed({offset_x_ff, 6'b0});
        st20_obj_y_ff <= $signed({{6{st10_vertex_y_ff2[15]}}, st10_vertex_y_ff2}) + $signed({offset_y_ff, 6'b0});
        st20_obj_z_ff <= $signed({{6{st10_vertex_z_ff2[15]}}, st10_vertex_z_ff2}) + $signed({offset_z_ff, 6'b0});
        st20_step_ff <= (phase == 1'b1) ? 1'b0 : 1'b1; //phase가 0 -> 1일떄 st10 레지스터가 업데이트 되므로 다음 클럭에 0을 넣어줌.
        st20_valid_ff <= st10_valid_ff2;

        st30_valid_ff <= st20_valid_ff && (~st20_step_ff); //st20_valid_ff가 1이고 st20_step_ff가 0일때만 st30_valid_ff에 1을 저장함.
        st40_valid_ff <= st30_valid_ff;
        st50_valid_ff <= st40_valid_ff;
        st60_valid_ff <= st50_valid_ff;
        
        st70_dsp0_p_ff <= dsp0_p;
        st70_dsp1_p_ff <= dsp1_p;
        st70_valid_ff <= st60_valid_ff;

        cam_out <= $signed(st80_total_sum_comb[43:12]); //출력값인 SQ16.28의 합에서 SQ15.16으로 변환해야 하므로 소수점 12자리를 버려서 비트 추출함.
        cam_valid <= st70_valid_ff;
    end
end

//2클럭에 한 번씩 전진해야 하는 플립플롭
always @(posedge clk) begin
    if (reset) begin
        st10_valid_ff2 <= 0;
        st10_vertex_x_ff2 <= 0;
        st10_vertex_y_ff2 <= 0;
        st10_vertex_z_ff2 <= 0;
    end 
    else if (phase == 1'b0) begin  // <--- Clock Enable 방식! 값 없데이트.
        if(bubble_insert_comb) begin
            st10_valid_ff2 <= 0; //버블 삽입!!!!
        end
        else begin
            st10_valid_ff2 <= 1;
        end
        st10_vertex_x_ff2 <= vertex_x;
        st10_vertex_y_ff2 <= vertex_y;
        st10_vertex_z_ff2 <= vertex_z;
    end
    else if (phase == 1'b1) begin // phase == 1'b1 일 때는 이전 값을 그대로 유지(Hold)
        st10_valid_ff2 <= st10_valid_ff2;
        st10_vertex_x_ff2 <= st10_vertex_x_ff2;
        st10_vertex_y_ff2 <= st10_vertex_y_ff2;
        st10_vertex_z_ff2 <= st10_vertex_z_ff2;
    end
end

endmodule