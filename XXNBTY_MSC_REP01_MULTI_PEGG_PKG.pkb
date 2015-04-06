create or replace PACKAGE BODY       XXNBTY_MSCREP01_MULTI_PEGG_PKG
/*
Package Name	: XXNBTY_MULTI_PEGGING_REP_PKG
Authorâ€™s name	: Mark Anthony Geamoga
Date written	: 12-FEB-2015
RICEFW Object id: 
Description		: Package that will generate multi-pegging report details.
Program Style	: 

Maintenance History:
Date 		   Issue# 			    Name 				                  Remarks
-----------   -------- 				---- 				            ------------------------------------------
12-FEB-2015 		  	        Mark Anthony Geamoga  		Initial development.
25-FEB-2015            	    	Mark Anthony Geamoga		Finished development except for BLEND.
03-MAR-2015 			        Albert John Flores			Added the conversion of date for the concurrent program
03-MAR-2015            	    	Mark Anthony Geamoga		Added BLEND ICC and consolidated with Albert's modification.
04-MAR-2015            	    	Mark Anthony Geamoga		Added Validations in the root selection 
05-MAR-2015				        Albert John Flores			Added the procedure for the request id identifier
13-MAR-2015						Albert John Flores			Finalized the Package with the parameters passed to be used by the XML Publisher
20-MAR-2015						Albert John Flores			Added Review points due to performance Issues
25-MAR-2015						Albert John Flores			Added procedure get_catalog_pr for items in vcp to staging table
26-MAR-2015						Albert John Flores			Added Function for the planned order demand query
30-MAR-2015						Albert John Flores			Modified For the incorrect details
*/
----------------------------------------------------------------------
IS
	--Function xxnbty_get_catalog_fn --Added 26/03/2015 Albert Flores
	FUNCTION xxnbty_get_catalog_fn( p_segment1 IN VARCHAR2 , p_org IN NUMBER)  RETURN VARCHAR2 IS  
	l_attribute1 	VARCHAR2(1000);
	BEGIN 

	  SELECT  icc 
	  INTO l_attribute1
	  FROM xxnbty_catalog_staging_tbl  
	  WHERE 	item_name  		= p_segment1
	  AND 		organization_id = p_org;

	  RETURN l_attribute1;
    
      EXCEPTION
      WHEN OTHERS THEN
      RETURN NULL;

    END;


	--procedure that will fetch records from ebs to vcp for catalog groups staging table xxnbty_catalog_staging_tbl
	PROCEDURE get_catalog_pr( errbuf	OUT VARCHAR2
							 ,retcode	OUT NUMBER) --3/25/2015 Albert Flores
	IS

	  TYPE get_icc_temp_tab   IS TABLE OF xxnbty_catalog_staging_tbl%ROWTYPE;

		
	  g_icc_rec			  get_icc_temp_tab := get_icc_temp_tab();   
	  c_get_icc 		  SYS_REFCURSOR;  	
	  l_get_icc_query     VARCHAR2(4000);
    
    v_step          number;
    v_mess          varchar2(500);
	-- Get DB Link from VCP to EBS
  
	  CURSOR icc_dbLink
	  IS
	  SELECT mai.M2A_DBLINK
			,mai.instance_id -- 3/25/2015 A Flores   
		FROM msc_apps_instances mai
	   WHERE mai.instance_code = 'EBS';
	 

	BEGIN
    v_step := 1;
    DELETE FROM xxnbty_catalog_staging_tbl;
    COMMIT;
    
	  v_step := 2;
    -- Get DB Link from VCP to EBS
	  OPEN icc_dbLink;
	  FETCH icc_dbLink INTO g_icc_db_link , g_instance_id;
	  CLOSE icc_dbLink;

    v_step := 3;
	l_get_icc_query := 'SELECT   msi_ebs.inventory_item_id inventory_item_id '
							||' ,msi_ebs.segment1 item_name '
							||' ,msi_ebs.organization_id organization_id '
							||' ,DECODE(NVL(emsieb.c_ext_attr2, ecg.catalog_group) '
								||' , '''|| icc_rm_constant ||''', NVL(emsieb.c_ext_attr2, ecg.catalog_group) '
								||' , '''|| icc_bl_constant ||''', NVL(emsieb.c_ext_attr2, ecg.catalog_group) '
								||' , '''|| icc_fg_constant ||''', NVL(emsieb.c_ext_attr2, ecg.catalog_group) '
								||' , ''FP Retail-Direct Consumer'', '''|| icc_fg_constant ||''' '
								||' , ''SFG - Consumer Direct'', '''|| icc_fg_constant ||''' '
								||' ,'''|| icc_dd_constant ||''', NVL(emsieb.c_ext_attr2, ecg.catalog_group),'''|| icc_bc_constant ||''') icc '
							||' ,emsieb.c_ext_attr2 blend '	
							||' ,ecg.catalog_group catalog_group '								
					 ||' FROM mtl_system_items@'|| g_icc_db_link ||' msi_ebs '
								||' ,ego_catalog_groups_v@'|| g_icc_db_link ||' ecg '
								||' ,ego_mtl_sy_items_ext_b@'|| g_icc_db_link ||' emsieb '
								||' ,msc_system_items msi_ascp '
					 ||' WHERE ecg.catalog_group_id 	  = msi_ebs.item_catalog_group_id '
					 ||' AND   msi_ebs.organization_id    = emsieb.organization_id (+) '
					 ||' AND   msi_ebs.inventory_item_id  = emsieb.inventory_item_id (+) '
					 ||' AND   emsieb.c_ext_attr2(+)   	  = '''|| icc_bl_constant ||''' '
					 ||' AND   msi_ebs.segment1        	  = msi_ascp.item_name '
					 ||' AND   msi_ebs.organization_id 	  = msi_ascp.organization_id '
					 ||' AND   msi_ascp.plan_id    	   	  = '''|| plan_id_constant ||''' '
					 ||' AND   msi_ascp.sr_instance_id 	  = '''|| g_instance_id ||''' ' ;
					 
    v_step := 4;
		OPEN c_get_icc FOR l_get_icc_query;
		LOOP
		 FETCH c_get_icc BULK COLLECT INTO g_icc_rec LIMIT c_limit;
			v_step := 5;
        FORALL i IN 1..g_icc_rec.COUNT	  
        INSERT /*+APPEND*/ INTO xxnbty_catalog_staging_tbl VALUES g_icc_rec(i);      
        COMMIT;        
    EXIT WHEN c_get_icc%NOTFOUND;        
		END LOOP;
    v_step := 6;
    DBMS_OUTPUT.PUT_LINE('Successfully inserted' || g_icc_rec.COUNT|| ' records');
    FND_FILE.PUT_LINE(FND_FILE.LOG, 'Successfully inserted' || g_icc_rec.COUNT|| ' records');
		CLOSE c_get_icc;

		EXCEPTION
			WHEN OTHERS THEN
        v_mess := 'At step ['||v_step||'] for procedure get_catalog_pr - SQLCODE [' ||SQLCODE|| '] - ' ||substr(SQLERRM,1,100);
			  errbuf  := v_mess;
			  retcode := 2; 	
		
	END get_catalog_pr;	


	--main procedure
	PROCEDURE main_pr( errbuf        	 OUT VARCHAR2
                     ,retcode       	 OUT NUMBER
                     ,p_plan_name        msc_orders_v.compile_designator%TYPE
                     ,p_org_code         msc_orders_v.organization_code%TYPE
                     ,p_catalog_group	 VARCHAR2
                     ,p_planner_code	 msc_orders_v.planner_code%TYPE
                     ,p_purchased_flag   msc_orders_v.purchasing_enabled_flag%TYPE
                     ,p_item_name		 msc_orders_v.item_segments%TYPE
                     ,p_main_from_date	 VARCHAR2
                     ,p_main_to_date	 VARCHAR2)
	IS
	  l_err_msg		    VARCHAR(100);
      l_from_date 		DATE := TO_DATE (p_main_from_date, 'YYYY/MM/DD HH24:MI:SS');
      l_to_date   		DATE := TO_DATE (p_main_to_date, 'YYYY/MM/DD HH24:MI:SS');
	--  l_request_id    NUMBER := fnd_global.conc_request_id;

	  v_step          NUMBER;
	  v_mess          VARCHAR2(500);
	
	
	BEGIN

	--define last updated by and created by
    g_last_updated_by := fnd_global.user_id;
    g_created_by      := fnd_global.user_id;	 
    g_request_id	  := fnd_global.conc_request_id; --Applied for review points 3/20/2015 Albert Flores
	
	v_step := 1;
	--validate input parameters
	IF p_plan_name IS NULL THEN
		l_err_msg := 'Please enter Plan Name.';
	ELSIF p_org_code IS NULL THEN
		l_err_msg := 'Please enter Organization Code.';
	ELSIF p_main_from_date IS NULL THEN
		l_err_msg := 'Please enter From Date.';  
	ELSIF p_catalog_group IS NULL
	   AND p_planner_code IS NULL
	   AND p_item_name IS NULL THEN
		l_err_msg := 'Either ICC or Planner Code or Item is required to generate pegging report.';  
	ELSIF l_to_date < l_from_date THEN
		l_err_msg := 'To Date must be later than From Date.';
	END IF;   
	v_step := 2;
	IF l_err_msg IS NULL THEN --proceed if all parameters are valid     
	
		--get root report
		get_root_rep( errbuf 
                   ,retcode
                   ,p_plan_name
                   ,p_org_code
                   ,p_catalog_group
                   ,p_planner_code
                   ,p_purchased_flag
                   ,p_item_name
                   ,l_from_date
                   ,l_to_date);
	v_step := 3;			   
		--call concurrent program for xml publisher		   
		generate_pegging_report( errbuf   
                            ,retcode   
                            ,g_request_id
                            ,p_plan_name
                            ,p_org_code
                            ,p_catalog_group
                            ,p_planner_code
                            ,p_purchased_flag
                            ,p_item_name
                            ,p_main_from_date
                            ,p_main_to_date); 				   
    v_step := 4;               
	ELSE --display error encountered
	  DBMS_OUTPUT.PUT_LINE(l_err_msg);
      FND_FILE.PUT_LINE(FND_FILE.LOG, l_err_msg);
      retcode := 2;
	END IF;
	
	EXCEPTION
			WHEN OTHERS THEN
			  v_mess := 'At step ['||v_step||'] for procedure main_pr - SQLCODE [' ||SQLCODE|| '] - ' ||substr(SQLERRM,1,100);
			  errbuf  := v_mess;
			  retcode := 2;
	END main_pr;
	
	--procedure that will get root report
	PROCEDURE get_root_rep( errbuf        	 OUT VARCHAR2
                          ,retcode       	 OUT NUMBER
                          ,p_plan_name       msc_orders_v.compile_designator%TYPE
                          ,p_org_code        msc_orders_v.organization_code%TYPE
                          ,p_catalog_group	 VARCHAR2
                          ,p_planner_code	 msc_orders_v.planner_code%TYPE
                          ,p_purchased_flag  msc_orders_v.purchasing_enabled_flag%TYPE
                          ,p_item_name		 msc_orders_v.item_segments%TYPE
                          ,p_from_date	     msc_orders_v.new_due_date%TYPE
                          ,p_to_date		 msc_orders_v.new_due_date%TYPE)
	IS
	c_rep_root	           SYS_REFCURSOR; --3/20/2015 AFLORES
    l_rep_root     icc_tab_type;
	l_query	      VARCHAR2(4000);
	
	  v_step          NUMBER;
	  v_mess          VARCHAR2(500);	
	BEGIN
	v_step := 1;
	--get db link of EBS
	OPEN c_db_link;
	FETCH c_db_link INTO g_db_link;
	CLOSE c_db_link;
	v_step := 2;
	--dynamic query to retrieve root report
	l_query := ' SELECT   mov.item_segments item '
                       ||' ,mov.description item_description ' 
                       ||' ,mov.organization_code org_code ' 
                       ||' ,mtp.partner_name org_description '
                       ||' ,0 excess_qty '
                       ||' ,mov.order_type_text order_type ' 
                       ||' ,mov.new_due_date due_date ' 
                       ||' ,mov.order_number order_number ' 
                       ||' ,mov.quantity_rate order_quantity ' 
                       ||' ,NULL pegging_order_no '
                       ||' ,mov.lot_number lot_number ' 
                       ||' ,mov.expiration_date psd_expiry_date ' 
                       ||' ,mov.source_organization_code source_org ' 
                       ||' ,xcst.icc catalog_group' --3/25/2015 Albert Flores
                       ||' ,NULL '
                       ||' ,mov.plan_id '
                       ||' ,mov.organization_id '
                       ||' ,mov.inventory_item_id '
                       ||' ,mov.sr_instance_id '
                       ||' ,mov.transaction_id '
               ||' FROM     msc_orders_v mov ' 
                       ||' ,msc_trading_partners mtp ' 
                       ||' ,msc_plans mp '
					   ||' ,xxnbty_catalog_staging_tbl xcst '
               ||' WHERE   mov.organization_code       = mtp.organization_code '
               ||' AND     mov.item_segments           = xcst.item_name ' --3/25/2015 Albert Flores
               ||' AND     xcst.organization_id        = mtp.sr_tp_id ' --3/25/2015 Albert Flores
               ||' AND     mov.plan_id                 = mp.plan_id '
               ||' AND     mov.compile_designator      = mp.compile_designator '
               ||' AND     mov.source_table            = ''MSC_SUPPLIES'' '
               ||' AND     mov.category_set_id         = :1 '
               ||' AND     mp.plan_run_date IS NOT NULL '
               ||' AND     mov.new_due_date IS NOT NULL '
               ||' AND     mov.compile_designator      = :2 '
               ||' AND     mov.organization_code       = :3 '
               ||' AND     xcst.icc			           = NVL(:4, xcst.icc) '
               ||' AND     mov.planner_code            = NVL(:5, mov.planner_code) '
               ||' AND     mov.purchasing_enabled_flag = NVL(:6, mov.purchasing_enabled_flag) '
               ||' AND     xcst.item_name               = NVL(:7, xcst.item_name) '
               ||' AND     TRUNC(mov.new_due_date)    BETWEEN TRUNC(:8) AND TRUNC(:9) '
               ||' AND     mov.order_type_text         = ''Planned order'' ';
	v_step := 3;
	OPEN c_rep_root FOR l_query USING ctgry_id_constant
                                 ,p_plan_name
                                 ,p_org_code
                                 ,p_catalog_group
                                 ,p_planner_code
                                 ,p_purchased_flag
                                 ,p_item_name
                                 ,p_from_date
                                 ,p_to_date;
	v_step := 4;							 
   LOOP --loop_c_rep_root --3/20/2015 AFLORES
      
	  DBMS_OUTPUT.PUT_LINE('Starting FETCH c_rep_root');
      FND_FILE.PUT_LINE(FND_FILE.LOG, 'Starting FETCH c_rep_root');
   FETCH c_rep_root BULK COLLECT INTO l_rep_root LIMIT c_limit; --Applied for review points 3/20/2015 Albert Flores
   --CLOSE c_rep;
    v_step := 5;
      FOR i IN 1..l_rep_root.COUNT
      LOOP
      DBMS_OUTPUT.PUT_LINE('Inside FOR i IN 1..l_rep_root.COUNT [' || l_rep_root.COUNT || ']');
      FND_FILE.PUT_LINE(FND_FILE.LOG, 'Inside FOR i IN 1..l_rep_root.COUNT [' || l_rep_root.COUNT || ']'); 
		 --03/30/2015 Albert Flores
		 collect_rep( errbuf
				 ,retcode
				 ,l_rep_root(i));
	  	  
       --get pegging report of current root record
         get_pegging_details( errbuf
                             ,retcode
                             ,l_rep_root(i));
         
         g_rm_index   := g_temp_rec.COUNT;
         g_bl_index   := g_temp_rec.COUNT;
         g_bc_index   := g_temp_rec.COUNT;
         g_fg_index   := g_temp_rec.COUNT;
         g_dd_index   := g_temp_rec.COUNT;
                        
      END LOOP;
	v_step := 6;  
      DBMS_OUTPUT.PUT_LINE('Calling Populate temp Table');
      FND_FILE.PUT_LINE(FND_FILE.LOG, 'Calling Populate temp Table');  	  
      --dump collected records in temp table
      populate_temp_table( errbuf
                          ,retcode
                          ,g_temp_rec); 
     v_step := 7;                     
      DBMS_OUTPUT.PUT_LINE('Successfully inserted ' || TO_CHAR(g_temp_rec.COUNT, 'fm999,999,999,999,999') || ' in temp table.');
      FND_FILE.PUT_LINE(FND_FILE.LOG, 'Successfully inserted ' || TO_CHAR(g_temp_rec.COUNT, 'fm999,999,999,999,999') || ' in temp table.');

      g_temp_rec.DELETE;   
  
    
    EXIT WHEN c_rep_root%NOTFOUND; --3/20/2015 AFLORES
	v_step := 8;
  END LOOP; --loop_c_rep_root --3/20/2015 AFLORES
  CLOSE c_rep_root;  --3/20/2015 AFLORES  
	v_step := 9;
	EXCEPTION
			WHEN OTHERS THEN
			  v_mess := 'At step ['||v_step||'] for procedure get_root_rep - SQLCODE [' ||SQLCODE|| '] - ' ||substr(SQLERRM,1,100);
			  errbuf  := v_mess;
			  retcode := 2; 
	END get_root_rep;
   
   --procedure that will retrieve pegging report of root record
   PROCEDURE get_pegging_details( errbuf        OUT VARCHAR2
                                 ,retcode       OUT NUMBER
                                 ,p_pegging_rec icc_type)
   IS
      CURSOR c_get_pegging( p_plan_id           msc_flp_supply_demand_v3.plan_id%TYPE
                           ,p_organization_id   msc_flp_supply_demand_v3.organization_id%TYPE
                           ,p_item_id           msc_flp_supply_demand_v3.item_id%TYPE
                           ,p_sr_instance_id    msc_flp_supply_demand_v3.sr_instance_id%TYPE
                           ,p_transaction_id    msc_flp_supply_demand_v3.transaction_id%TYPE)
      IS
      SELECT pegging_id
        FROM msc_flp_supply_demand_v3
       WHERE plan_id = p_plan_id
         AND organization_id = p_organization_id
         AND item_id = p_item_id
         AND sr_instance_id = p_sr_instance_id
         AND transaction_id = p_transaction_id;
      
      --c_rep	         SYS_REFCURSOR; --3/20/2015 AFLORES
	  c_rep_root2	           SYS_REFCURSOR; --3/20/2015 AFLORES
      c_rep_order			   SYS_REFCURSOR; --3/20/2015 AFLORES
	  c_rep_demand 		   SYS_REFCURSOR; --3/20/2015 AFLORES
      l_pegging_rep  icc_tab_type;
      l_current_peg  icc_tab_type;
      l_orig_query	 VARCHAR2(5000);
      l_peg_query    VARCHAR2(6000);
      l_pegging_ids  VARCHAR2(6000);
      l_plan_id      NUMBER;
	  
	  v_step          NUMBER;
	  v_mess          VARCHAR2(500);	  
   BEGIN
    v_step := 1;
      DBMS_OUTPUT.PUT_LINE('start get pegging details ');
      FND_FILE.PUT_LINE(FND_FILE.LOG, 'start get pegging details ');  
      l_orig_query := ' SELECT mov.item_segments item '
                             ||' ,mov.description item_description '
                             ||' ,mov.organization_code org_code '
                             ||' ,mtp.partner_name org_description '
                             ||' ,DECODE(SIGN(mfsdv.demand_id), -1, mfsdv.pegged_qty, 0)  excess_qty '
                             ||' ,mov.order_type_text order_type '
                             ||' ,mov.new_due_date due_date '
                             ||' ,mov.order_number order_number '
                             ||' ,mfsdv.pegged_qty order_quantity '
                             ||' ,NULL pegging_order_no '
                             ||' ,mov.lot_number lot_number '
                             ||' ,mov.expiration_date psd_expiry_date '
                             ||' ,mov.source_organization_code source_org '
                             ||' ,xcst.icc catalog_group ' --3/25/2015 Albert Flores
                             ||' ,mfsdv.pegging_id '  
                             ||' ,mov.plan_id '
                             ||' ,mov.organization_id '
                             ||' ,mov.inventory_item_id '
                             ||' ,mov.sr_instance_id '
                             ||' ,mov.transaction_id '
                     ||' FROM     msc_orders_v mov '
                             ||' ,msc_trading_partners mtp '
                             ||' ,msc_plans mp '
							 ||' ,xxnbty_catalog_staging_tbl xcst '
                             ||' ,msc_flp_supply_demand_v3 mfsdv '
                     ||' WHERE   mov.organization_code       = mtp.organization_code '
                     ||' AND     mov.item_segments           = xcst.item_name ' --3/25/2015 Albert Flores
                     ||' AND     xcst.organization_id        = mtp.sr_tp_id ' --3/25/2015 Albert Flores
                     ||' AND     mov.plan_id                 = mp.plan_id '
                     ||' AND     mov.compile_designator      = mp.compile_designator '
                     ||' AND     mfsdv.transaction_id        = mov.transaction_id '
                     ||' AND     mfsdv.plan_id               = mov.plan_id '
                     ||' AND     mfsdv.organization_id       = mov.organization_id '
                     ||' AND     mfsdv.item_id               = mov.inventory_item_id '
                     ||' AND     mfsdv.sr_instance_id        = mov.sr_instance_id ';
      v_step := 2;
      l_peg_query := l_orig_query || ' AND mov.category_set_id   = :1 '
                                  || ' AND mov.plan_id           = :2 '
                                  || ' AND mov.organization_code = :3 '
                                  || ' AND mov.item_segments     = :4 '
                                  || ' AND mfsdv.transaction_id  = :5 ';
      v_step := 3;                           
      DBMS_OUTPUT.PUT_LINE( l_peg_query );
      FND_FILE.PUT_LINE(FND_FILE.LOG, l_peg_query );                                   
      DBMS_OUTPUT.PUT_LINE( ctgry_id_constant );
      FND_FILE.PUT_LINE(FND_FILE.LOG, ctgry_id_constant );
      DBMS_OUTPUT.PUT_LINE( p_pegging_rec.plan_id );
      FND_FILE.PUT_LINE(FND_FILE.LOG, p_pegging_rec.plan_id );
      DBMS_OUTPUT.PUT_LINE( p_pegging_rec.org_code );
      FND_FILE.PUT_LINE(FND_FILE.LOG, p_pegging_rec.org_code );
      DBMS_OUTPUT.PUT_LINE( p_pegging_rec.item );
      FND_FILE.PUT_LINE(FND_FILE.LOG, p_pegging_rec.item );
      DBMS_OUTPUT.PUT_LINE( p_pegging_rec.transaction_id );
      FND_FILE.PUT_LINE(FND_FILE.LOG, p_pegging_rec.transaction_id );
      
      OPEN c_rep_root2 FOR l_peg_query USING ctgry_id_constant
                                     ,p_pegging_rec.plan_id
                                     ,p_pegging_rec.org_code
                                     ,p_pegging_rec.item
                                     ,p_pegging_rec.transaction_id;
	  v_step := 4;							 
	  LOOP 	--loop_c_rep_root2 --3/20/2015 AFLORES
      DBMS_OUTPUT.PUT_LINE( 'inside open c_rep_root2' );
      FND_FILE.PUT_LINE(FND_FILE.LOG, 'inside open c_rep_root2' );   	  
      FETCH c_rep_root2 BULK COLLECT INTO l_pegging_rep LIMIT c_limit; --Applied for review points 3/20/2015 Albert Flores
      --CLOSE c_rep; --3/20/2015 AFLORES
      v_step := 5;
      FOR j IN 1..l_pegging_rep.COUNT
		LOOP
		  l_pegging_rep(j).pegging_order_no := p_pegging_rec.order_number;
         /*collect_rep( errbuf
                     ,retcode						--03/30/2015 Albert Flores
                     ,l_pegging_rep(j)); */
         --collect pegging ids of current level            
         l_pegging_ids := l_pegging_ids || l_pegging_rep(j).pegging_id || ',';
	  
      DBMS_OUTPUT.PUT_LINE('Inside FOR j IN 1..l_pegging_rep.COUNT [' || l_pegging_rep.COUNT || ']');
      FND_FILE.PUT_LINE(FND_FILE.LOG, 'Inside FOR j IN 1..l_pegging_rep.COUNT [' || l_pegging_rep.COUNT || ']'); 
	  
		END LOOP;
	  v_step := 6;		
      l_pegging_ids := RTRIM(l_pegging_ids, ',');   
	  
      DBMS_OUTPUT.PUT_LINE( 'outside open c_rep_root2' );
      FND_FILE.PUT_LINE(FND_FILE.LOG, 'outside open c_rep_root2' ); 
      l_peg_query := NULL; --clear dynamic query
      l_pegging_rep.DELETE; --clear collection
      v_step := 7;
      l_plan_id := p_pegging_rec.plan_id;
      --DBMS_OUTPUT.PUT_LINE('Order Number: ' || p_pegging_rec.order_number);   
      LOOP --loop_planned_order_demand
		DBMS_OUTPUT.PUT_LINE('Pegging IDs: ' || l_pegging_ids); 
		FND_FILE.PUT_LINE(FND_FILE.LOG, 'Plan IDs: ' || l_plan_id);
		FND_FILE.PUT_LINE(FND_FILE.LOG, 'Category IDs: ' || ctgry_id_constant);
		FND_FILE.PUT_LINE(FND_FILE.LOG, 'Pegging IDs: ' || l_pegging_ids); 		
		--planned order demand
		l_peg_query := ' SELECT mov.item_segments item '
                            ||'  ,mov.description item_description '
                            ||'  ,mov.organization_code org_code '
                            ||'  ,mtp.partner_name org_description '
                            ||'  ,DECODE(SIGN(mfsdv.demand_id), -1, mfsdv.pegged_qty, 0)  excess_qty '
                            ||'  ,mfsdv.origination_name order_type '
                            ||'  ,mfsdv.demand_date due_date '
                            ||'  ,mov.order_number order_number '
                            ||'  ,ABS(mfsdv.pegged_qty) order_quantity '
                            ||'  ,sub2.order_number pegging_order_no '
                            ||'  ,mov.lot_number lot_number '
                            ||'  ,mov.expiration_date psd_expiry_date '
                            ||'  ,mov.source_organization_code source_org '
                            --||'  ,xcst.icc catalog_group ' --3/25/2015 Albert Flores
							||'  ,XXNBTY_MSCREP01_MULTI_PEGG_PKG.xxnbty_get_catalog_fn(mov.item_segments,mtp.sr_tp_id)catalog_group ' --Added 26/03/2015 Albert Flores
                            ||'  ,mfsdv.pegging_id '
                            ||'  ,mov.plan_id '
                            ||'  ,mov.organization_id '
                            ||'  ,mov.inventory_item_id '
                            ||'  ,mov.sr_instance_id '
                            ||'  ,mfsdv.transaction_id '
                     ||' FROM     msc_orders_v mov '
                            ||'  ,msc_trading_partners mtp '
                            ||'  ,msc_plans mp '
                            ||'  ,(SELECT mfsdv2.pegging_id '
							||'			 ,mov2.order_number '
							||'		FROM msc_orders_v mov2  '
							||'			 ,msc_flp_supply_demand_v3 mfsdv2 '
							||'		WHERE mfsdv2.transaction_id = mov2.transaction_id '
							||'		AND   mfsdv2.plan_id          = mov2.plan_id '
							||'		AND   mfsdv2.organization_id  = mov2.organization_id '
							||'		AND   mfsdv2.item_id          = mov2.inventory_item_id '
							||'		AND   mfsdv2.sr_instance_id   = mov2.sr_instance_id '
							||'		AND   mov2.plan_id            = '|| l_plan_id ||' '
							||'		AND   mov2.category_set_id    = '|| ctgry_id_constant ||') sub2 '
                            ||'  ,msc_flp_supply_demand_v3 mfsdv '
                             --||' ,xxnbty_catalog_staging_tbl xcst ' --Added 26/03/2015 Albert Flores
                    ||'  WHERE   mov.organization_code       = mtp.organization_code '
                    --||'  AND     mov.item_segments           = xcst.item_name ' --3/25/2015 Albert Flores
                    --||'  AND     xcst.organization_id        = mtp.sr_tp_id ' --3/25/2015 Albert Flores
                    ||'  AND     mov.plan_id                 = mp.plan_id '
                    ||'  AND     mov.compile_designator      = mp.compile_designator '
                    ||'  AND     mfsdv.demand_id             = mov.transaction_id '
                    ||'  AND     mfsdv.plan_id               = mov.plan_id '
                    ||'  AND     mfsdv.organization_id       = mov.organization_id '
                    ||'  AND     mfsdv.item_id               = mov.inventory_item_id '
                    ||'  AND     mfsdv.sr_instance_id        = mov.sr_instance_id '
                    ||'  AND     mov.source_table            = ''MSC_DEMANDS'' '
					||'  AND     sub2.pegging_id = mfsdv.prev_pegging_id '
					||'  AND mov.category_set_id     = ' || ctgry_id_constant || ' '
					||'  AND mov.plan_id             = '|| l_plan_id ||' '
					||'  AND mfsdv.prev_pegging_id   IN (' || l_pegging_ids || ') ' 
					||'  ORDER BY mfsdv.pegging_id desc';
		 v_step := 8;
         OPEN c_rep_demand FOR l_peg_query; --3/20/2015 AFLORES
		 v_step := 9;
		 LOOP --loop_c_rep_demand --3/20/2015 AFLORES
		 FETCH c_rep_demand BULK COLLECT INTO l_current_peg LIMIT c_limit; --Applied for review points 3/20/2015 Albert Flores
			 --CLOSE c_rep;      --3/20/2015 AFLORES
		v_step := 10; 
			 l_peg_query := NULL; --clear dynamic query
			 l_pegging_ids := NULL; --clear collected pegging id
			 
			 FOR k IN 1..l_current_peg.COUNT			 
			 LOOP 
			  DBMS_OUTPUT.PUT_LINE('Inside FOR k IN 1..l_current_peg.COUNT [' || l_current_peg.COUNT || ']');
			  FND_FILE.PUT_LINE(FND_FILE.LOG, 'Inside FOR k IN 1..l_current_peg.COUNT [' || l_current_peg.COUNT || ']'); 			 
				
				collect_rep( errbuf
							,retcode
							,l_current_peg(k));
				v_step := 11;
				--planned order
				l_peg_query := l_orig_query || ' AND mov.category_set_id            = :1 '
											|| ' AND mov.plan_id                    = :2 '
											|| ' AND mov.item_segments				= :3 '
											|| ' AND mov.organization_code 			= :4 '
											|| ' AND mov.sr_instance_id             = :5 '
											|| ' AND mov.transaction_id             = :6 '
											|| ' AND mfsdv.pegging_id               = :7 ';
				v_step := 12;						
				OPEN c_rep_order FOR l_peg_query USING ctgry_id_constant
												,l_current_peg(k).plan_id
												,l_current_peg(k).item
												,l_current_peg(k).org_code
												,l_current_peg(k).sr_instance_id
												,l_current_peg(k).transaction_id
												,l_current_peg(k).pegging_id;
				v_step := 13;								
				LOOP --loop_c_rep_order	3/20/2015 AFLORES							
				FETCH c_rep_order BULK COLLECT INTO l_pegging_rep LIMIT c_limit; --Applied for review points 3/20/2015 Albert Flores
					--CLOSE c_rep; 3/20/2015 AFLORES     
				v_step := 14;	
					--collect pegging ids from planned order demand  
					l_pegging_ids := l_pegging_ids || l_current_peg(k).pegging_id || ',';
					
					FOR j IN 1..l_pegging_rep.COUNT
					LOOP
					v_step := 15;
					l_pegging_rep(j).pegging_order_no := l_current_peg(k).order_number;
					DBMS_OUTPUT.PUT_LINE('Inside FOR FOR j IN 1..l_pegging_rep.COUNT [' || l_pegging_rep.COUNT || ']');
					FND_FILE.PUT_LINE(FND_FILE.LOG, 'Inside FOR FOR j IN 1..l_pegging_rep.COUNT [' || l_pegging_rep.COUNT || ']'); 	
					   collect_rep( errbuf
								   ,retcode
								   ,l_pegging_rep(j));
					END LOOP;
					v_step := 16;
				EXIT WHEN c_rep_order%NOTFOUND; --3/20/2015 AFLORES
				v_step := 17;
				END LOOP; --loop_c_rep_order --3/20/2015 AFLORES
				CLOSE c_rep_order; --3/20/2015 AFLORES
			 v_step := 18;	
			 END LOOP;
			 
			 l_pegging_ids := RTRIM(l_pegging_ids, ',');
			 
			 EXIT WHEN l_pegging_ids IS NULL;
		 v_step := 19;
		 EXIT WHEN c_rep_demand%NOTFOUND;
		 END LOOP; --loop_c_rep_demand --3/20/2015 AFLORES
		 CLOSE c_rep_demand;
	     v_step := 20;
	  END LOOP; --loop_planned_order_demand
	  

	  v_step := 21;
	  EXIT WHEN c_rep_root2%NOTFOUND; --3/20/2015 AFLORES
	  END LOOP; --loop_c_rep_root2 --3/20/2015 AFLORES
	  CLOSE c_rep_root2; --3/20/2015 AFLORES
	  v_step := 22;
      l_peg_query := NULL; --clear dynamic query
      l_pegging_rep.DELETE; --clear collection 
	  
	EXCEPTION
			WHEN OTHERS THEN
			  v_mess := 'At step ['||v_step||'] for procedure get_pegging_details - SQLCODE [' ||SQLCODE|| '] - ' ||substr(SQLERRM,1,100);
			  errbuf  := v_mess;
			  retcode := 2;  
         
   END get_pegging_details;
	
	--procedure that will re-assign records to designated icc type
	PROCEDURE collect_rep ( errbuf   OUT VARCHAR2
                          ,retcode  OUT NUMBER
                          ,p_icc	       icc_type)
	IS
	  v_step          NUMBER;
	  v_mess          VARCHAR2(500);	
	BEGIN
	DBMS_OUTPUT.PUT_LINE('Collect_rep Started');
	FND_FILE.PUT_LINE(FND_FILE.LOG, 'Collect_rep Started');
					
		IF p_icc.catalog_group = icc_rm_constant THEN
         g_rm_index                                   := g_rm_index + 1;
		 v_step := 1;
         IF NOT g_temp_rec.EXISTS(g_rm_index) THEN
            g_temp_rec.EXTEND;
         END IF;
		 g_temp_rec(g_rm_index).record_id              := g_rm_index;
         g_temp_rec(g_rm_index).item_rm 			   := p_icc.item;
         g_temp_rec(g_rm_index).item_desc_rm		   := p_icc.item_desc;
         g_temp_rec(g_rm_index).org_code_rm			   := p_icc.org_code;
         g_temp_rec(g_rm_index).org_desc_rm			   := p_icc.org_desc;
         g_temp_rec(g_rm_index).excess_qty_rm		   := p_icc.excess_qty;
         g_temp_rec(g_rm_index).order_type_rm		   := p_icc.order_type;
         g_temp_rec(g_rm_index).due_date_rm			   := p_icc.due_date;
         g_temp_rec(g_rm_index).lot_number_rm		   := p_icc.lot_number;
         g_temp_rec(g_rm_index).psd_expiry_date_rm	   := p_icc.psd_expiry_date;
         g_temp_rec(g_rm_index).order_number_rm		   := p_icc.order_number;
         g_temp_rec(g_rm_index).source_org_rm		   := p_icc.source_org;
         g_temp_rec(g_rm_index).order_qty_rm		   := p_icc.order_qty;
         g_temp_rec(g_rm_index).pegging_order_no_rm	   := p_icc.pegging_order_no;
		 --Applied for review points 3/20/2015 Albert Flores
		 g_temp_rec(g_rm_index).last_update_date       := SYSDATE;
		 g_temp_rec(g_rm_index).last_updated_by        := g_last_updated_by;
		 g_temp_rec(g_rm_index).last_update_login      := g_last_updated_by;
		 g_temp_rec(g_rm_index).creation_date          := SYSDATE;
		 g_temp_rec(g_rm_index).created_by             := g_created_by;
		 g_temp_rec(g_rm_index).request_id             := g_request_id;
		 --Applied 3/31/2015 Albert Flores
		 g_temp_rec(g_rm_index).pegging_id             := p_icc.pegging_id;
		 
		 DBMS_OUTPUT.PUT_LINE('Raw Material Inserted');
         FND_FILE.PUT_LINE(FND_FILE.LOG, 'Raw Material Inserted');                                              
      
	  ELSIF p_icc.catalog_group = icc_bl_constant THEN
         g_bl_index                                    := g_bl_index + 1;
		 v_step := 2;
         IF NOT g_temp_rec.EXISTS(g_bl_index) THEN
            g_temp_rec.EXTEND;
         END IF;
		 g_temp_rec(g_bl_index).record_id              := g_bl_index;
         g_temp_rec(g_bl_index).item_bl 			   := p_icc.item;
         g_temp_rec(g_bl_index).item_desc_bl		   := p_icc.item_desc;
         g_temp_rec(g_bl_index).org_code_bl			   := p_icc.org_code;
         g_temp_rec(g_bl_index).org_desc_bl			   := p_icc.org_desc;
         g_temp_rec(g_bl_index).excess_qty_bl		   := p_icc.excess_qty;
         g_temp_rec(g_bl_index).order_type_bl		   := p_icc.order_type;
         g_temp_rec(g_bl_index).due_date_bl			   := p_icc.due_date;
         g_temp_rec(g_bl_index).lot_number_bl		   := p_icc.lot_number;
         g_temp_rec(g_bl_index).psd_expiry_date_bl	   := p_icc.psd_expiry_date;
         g_temp_rec(g_bl_index).order_number_bl		   := p_icc.order_number;
         g_temp_rec(g_bl_index).source_org_bl		   := p_icc.source_org;
         g_temp_rec(g_bl_index).order_qty_bl		   := p_icc.order_qty;
         g_temp_rec(g_bl_index).pegging_order_no_bl	   := p_icc.pegging_order_no;
		 --Applied for review points 3/20/2015 Albert Flores
		 g_temp_rec(g_bl_index).last_update_date       := SYSDATE;
		 g_temp_rec(g_bl_index).last_updated_by        := g_last_updated_by;
		 g_temp_rec(g_bl_index).last_update_login      := g_last_updated_by;
		 g_temp_rec(g_bl_index).creation_date          := SYSDATE;
		 g_temp_rec(g_bl_index).created_by             := g_created_by;
		 g_temp_rec(g_bl_index).request_id             := g_request_id;		
		 --Applied 3/31/2015 Albert Flores
		 g_temp_rec(g_bl_index).pegging_id             := p_icc.pegging_id;
		 
		 DBMS_OUTPUT.PUT_LINE('Blend Inserted');
         FND_FILE.PUT_LINE(FND_FILE.LOG, 'Blend Inserted');  		 
		 
      ELSIF p_icc.catalog_group = icc_bc_constant THEN
         g_bc_index                                    := g_bc_index + 1;
		 v_step := 3;
         IF NOT g_temp_rec.EXISTS(g_bc_index) THEN
            g_temp_rec.EXTEND;
         END IF;
		 g_temp_rec(g_bc_index).record_id              := g_bc_index;
         g_temp_rec(g_bc_index).item_bc 			   := p_icc.item;
         g_temp_rec(g_bc_index).item_desc_bc		   := p_icc.item_desc;
         g_temp_rec(g_bc_index).org_code_bc			   := p_icc.org_code;
         g_temp_rec(g_bc_index).org_desc_bc			   := p_icc.org_desc;
         g_temp_rec(g_bc_index).excess_qty_bc		   := p_icc.excess_qty;
         g_temp_rec(g_bc_index).order_type_bc		   := p_icc.order_type;
         g_temp_rec(g_bc_index).due_date_bc			   := p_icc.due_date;
         g_temp_rec(g_bc_index).lot_number_bc		   := p_icc.lot_number;
         g_temp_rec(g_bc_index).psd_expiry_date_bc	   := p_icc.psd_expiry_date;
         g_temp_rec(g_bc_index).order_number_bc		   := p_icc.order_number;
         g_temp_rec(g_bc_index).source_org_bc		   := p_icc.source_org;
         g_temp_rec(g_bc_index).order_qty_bc		   := p_icc.order_qty;
         g_temp_rec(g_bc_index).pegging_order_no_bc	   := p_icc.pegging_order_no;
		 --Applied for review points 3/20/2015 Albert Flores
		 g_temp_rec(g_bc_index).last_update_date       := SYSDATE;
		 g_temp_rec(g_bc_index).last_updated_by        := g_last_updated_by;
		 g_temp_rec(g_bc_index).last_update_login      := g_last_updated_by;
		 g_temp_rec(g_bc_index).creation_date          := SYSDATE;
		 g_temp_rec(g_bc_index).created_by             := g_created_by;
		 g_temp_rec(g_bc_index).request_id             := g_request_id;	
		 --Applied 3/31/2015 Albert Flores
		 g_temp_rec(g_bc_index).pegging_id             := p_icc.pegging_id;
		 
		 DBMS_OUTPUT.PUT_LINE('Bulk Inserted');
         FND_FILE.PUT_LINE(FND_FILE.LOG, 'Bulk Inserted');  		 
		 
      ELSIF p_icc.catalog_group = icc_fg_constant THEN
         g_fg_index                                    := g_fg_index + 1;
		 v_step := 4;
         IF NOT g_temp_rec.EXISTS(g_fg_index) THEN
            g_temp_rec.EXTEND;
         END IF;
		 g_temp_rec(g_fg_index).record_id              := g_fg_index;
         g_temp_rec(g_fg_index).item_fg 			   := p_icc.item;
		 g_temp_rec(g_fg_index).item_desc_fg		   := p_icc.item_desc;
		 g_temp_rec(g_fg_index).org_code_fg			   := p_icc.org_code;
		 g_temp_rec(g_fg_index).org_desc_fg			   := p_icc.org_desc;
		 g_temp_rec(g_fg_index).excess_qty_fg		   := p_icc.excess_qty;
		 g_temp_rec(g_fg_index).order_type_fg		   := p_icc.order_type;
		 g_temp_rec(g_fg_index).due_date_fg			   := p_icc.due_date;
		 g_temp_rec(g_fg_index).lot_number_fg		   := p_icc.lot_number;
		 g_temp_rec(g_fg_index).psd_expiry_date_fg	   := p_icc.psd_expiry_date;
		 g_temp_rec(g_fg_index).order_number_fg		   := p_icc.order_number;
		 g_temp_rec(g_fg_index).source_org_fg		   := p_icc.source_org;
		 g_temp_rec(g_fg_index).order_qty_fg		   := p_icc.order_qty;
		 g_temp_rec(g_fg_index).pegging_order_no_fg	   := p_icc.pegging_order_no;
		 --Applied for review points 3/20/2015 Albert Flores
		 g_temp_rec(g_fg_index).last_update_date       := SYSDATE;
		 g_temp_rec(g_fg_index).last_updated_by        := g_last_updated_by;
		 g_temp_rec(g_fg_index).last_update_login      := g_last_updated_by;
		 g_temp_rec(g_fg_index).creation_date          := SYSDATE;
		 g_temp_rec(g_fg_index).created_by             := g_created_by;
		 g_temp_rec(g_fg_index).request_id             := g_request_id;	
		 --Applied 3/31/2015 Albert Flores
		 g_temp_rec(g_fg_index).pegging_id             := p_icc.pegging_id;
		 
		 DBMS_OUTPUT.PUT_LINE('Finished good Inserted');
         FND_FILE.PUT_LINE(FND_FILE.LOG, 'Finished good Inserted');  		 
		 
      ELSIF p_icc.catalog_group = icc_dd_constant THEN
         g_dd_index                                    := g_dd_index + 1;
		 v_step := 5;
         IF NOT g_temp_rec.EXISTS(g_dd_index) THEN
            g_temp_rec.EXTEND;
         END IF;
		 g_temp_rec(g_dd_index).record_id              := g_dd_index;
         g_temp_rec(g_dd_index).item_dd 			   := p_icc.item;
         g_temp_rec(g_dd_index).item_desc_dd		   := p_icc.item_desc;
         g_temp_rec(g_dd_index).org_code_dd			   := p_icc.org_code;
         g_temp_rec(g_dd_index).org_desc_dd			   := p_icc.org_desc;
         g_temp_rec(g_dd_index).excess_qty_dd		   := p_icc.excess_qty;
         g_temp_rec(g_dd_index).order_type_dd		   := p_icc.order_type;
         g_temp_rec(g_dd_index).due_date_dd			   := p_icc.due_date;
         g_temp_rec(g_dd_index).lot_number_dd		   := p_icc.lot_number;
         g_temp_rec(g_dd_index).psd_expiry_date_dd	   := p_icc.psd_expiry_date;
         g_temp_rec(g_dd_index).order_number_dd		   := p_icc.order_number;
         g_temp_rec(g_dd_index).source_org_dd		   := p_icc.source_org;
         g_temp_rec(g_dd_index).order_qty_dd		   := p_icc.order_qty;
         g_temp_rec(g_dd_index).pegging_order_no_dd	   := p_icc.pegging_order_no;
		 --Applied for review points 3/20/2015 Albert Flores
		 g_temp_rec(g_dd_index).last_update_date       := SYSDATE;
		 g_temp_rec(g_dd_index).last_updated_by        := g_last_updated_by;
		 g_temp_rec(g_dd_index).last_update_login      := g_last_updated_by;
		 g_temp_rec(g_dd_index).creation_date          := SYSDATE;
		 g_temp_rec(g_dd_index).created_by             := g_created_by;
		 g_temp_rec(g_dd_index).request_id             := g_request_id;	
		--Applied 3/31/2015 Albert Flores
		 g_temp_rec(g_dd_index).pegging_id             := p_icc.pegging_id;

		 DBMS_OUTPUT.PUT_LINE('Deals Inserted');
         FND_FILE.PUT_LINE(FND_FILE.LOG, 'Deals Inserted');  
	  v_step := 5; 
      END IF;
      
	EXCEPTION
			WHEN OTHERS THEN
			  v_mess := 'At step ['||v_step||'] for procedure collect_rep - SQLCODE [' ||SQLCODE|| '] - ' ||substr(SQLERRM,1,100);
			  errbuf  := v_mess;
			  retcode := 2; 	
	END collect_rep;
  
	--procedure that will populate temp table
	PROCEDURE populate_temp_table( errbuf   		OUT VARCHAR2
                                  ,retcode  		 OUT NUMBER
                                  ,p_temp_tab	     temp_tab_type)
	IS
	--l_request_id    NUMBER := fnd_global.conc_request_id;
	  v_step          NUMBER;
	  v_mess          VARCHAR2(500);	
	
	BEGIN
	v_step := 1;
      --delete old records
      DELETE FROM xxnbty_pegging_temp_tbl
      WHERE (TRUNC(SYSDATE) - TO_DATE(creation_date)) > 5;
      COMMIT; 
	v_step := 2;  
      --insert new records 
  		 DBMS_OUTPUT.PUT_LINE('Record Inserted');
         FND_FILE.PUT_LINE(FND_FILE.LOG, 'Record Inserted');  
      FORALL i IN 1..p_temp_tab.COUNT	  
      INSERT /*+APPEND*/ INTO xxnbty_pegging_temp_tbl VALUES p_temp_tab(i); --Applied for review points 3/20/2015 Albert Flores
      COMMIT;
	v_step := 3;  
      /*
	  UPDATE xxnbty_pegging_temp_tbl
      SET  last_update_date  = SYSDATE
          ,last_updated_by   = g_last_updated_by
          ,last_update_login = g_last_updated_by						    --Removed for review points 3/20/2015 Albert Flores
          ,creation_date     = SYSDATE
          ,created_by        = g_created_by
          ,request_id        = l_request_id
	  WHERE  request_id is null;
          
      COMMIT;    
	  */
	  
	EXCEPTION
			WHEN OTHERS THEN
			  v_mess := 'At step ['||v_step||'] for procedure populate_temp_table - SQLCODE [' ||SQLCODE|| '] - ' ||substr(SQLERRM,1,100);
			  errbuf  := v_mess;
			  retcode := 2;  
	END populate_temp_table;
	
	PROCEDURE generate_pegging_report( errbuf   		 OUT VARCHAR2
                                 	  ,retcode  		 OUT NUMBER
                                      ,x_request_id	  	 NUMBER
									  ,p_plan_name       msc_orders_v.compile_designator%TYPE
									  ,p_org_code        msc_orders_v.organization_code%TYPE
									  ,p_catalog_group	 VARCHAR2
									  ,p_planner_code	 msc_orders_v.planner_code%TYPE
									  ,p_purchased_flag  msc_orders_v.purchasing_enabled_flag%TYPE
									  ,p_item_name		 msc_orders_v.item_segments%TYPE
									  ,p_main_from_date	 VARCHAR2
									  ,p_main_to_date	 VARCHAR2)
    IS
	    r_request_id  NUMBER;
	    l_flag1        BOOLEAN;
	    l_flag2        BOOLEAN;
	
	BEGIN
	
    --create layout for Pegging Report
    l_flag1 := FND_REQUEST.ADD_LAYOUT ('XXNBTY',
                                      'XXNBTY_MSC_GEN_PEG_REPORT',
                                      'En',
                                      'US',
                                      'EXCEL' );
    IF (l_flag1) THEN
      FND_FILE.PUT_LINE(FND_FILE.LOG, 'The layout has been submitted');
    ELSE
      FND_FILE.PUT_LINE(FND_FILE.LOG, 'The layout has not been submitted');
    END IF;

    r_request_id := FND_REQUEST.SUBMIT_REQUEST(application   => 'XXNBTY'
                                               ,program      => 'XXNBTY_MSC_GEN_PEG_REPORT'
                                               ,start_time   => NULL --Applied for review points 3/20/2015 Albert Flores
                                               ,sub_request  => FALSE
                                               ,Argument1 	 => x_request_id
											   ,Argument2	 => p_plan_name
											   ,Argument3	 => p_org_code
											   ,Argument4 	 => p_catalog_group
											   ,Argument5	 => p_planner_code
											   ,Argument6	 => p_purchased_flag
											   ,Argument7 	 => p_item_name
											   ,Argument8	 => p_main_from_date
											   ,Argument9	 => p_main_to_date
                                               );
    FND_CONCURRENT.AF_COMMIT;
    
    EXCEPTION
    WHEN OTHERS THEN
      retcode := 2;
      errbuf := SQLERRM;
    
  END generate_pegging_report;                       
                                      
	
END XXNBTY_MSCREP01_MULTI_PEGG_PKG;
/
show errors;
