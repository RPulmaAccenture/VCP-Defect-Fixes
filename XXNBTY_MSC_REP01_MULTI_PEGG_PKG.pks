create or replace PACKAGE      XXNBTY_MSCREP01_MULTI_PEGG_PKG
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
*/
----------------------------------------------------------------------
IS
	--cursor that will retrieve dblink of EBS
	CURSOR c_db_link
	IS
	SELECT mai.m2a_dblink
	  FROM msc_apps_instances mai
	 WHERE mai.instance_code = 'EBS';
   
  g_last_updated_by   NUMBER(15);
  g_created_by        NUMBER(15);
  g_request_id		  NUMBER;
  c_limit             CONSTANT NUMBER := 1000; --Applied for review points 3/20/2015 Albert Flores
	 
   TYPE icc_type IS RECORD ( item 				   msc_orders_v.item_segments%TYPE
                            ,item_desc 	      	   msc_orders_v.description%TYPE
                            ,org_code 			   msc_orders_v.organization_code%TYPE
                            ,org_desc 			   msc_trading_partners.partner_name%TYPE 
                            ,excess_qty 		   msc_full_pegging.allocated_quantity%TYPE
                            ,order_type 		   msc_orders_v.order_type_text%TYPE
                            ,due_date 			   msc_orders_v.new_due_date%TYPE
                            ,order_number		   msc_orders_v.order_number%TYPE
                            ,order_qty			   msc_orders_v.quantity_rate%TYPE
                            ,pegging_order_no 	   xxnbty_pegging_temp_tbl.pegging_order_no_dd%TYPE
                            ,lot_number 		   msc_orders_v.lot_number%TYPE
                            ,psd_expiry_date 	   msc_orders_v.expiration_date%TYPE
                            ,source_org			   msc_orders_v.source_organization_code%TYPE
                            ,catalog_group		   VARCHAR2(100)
                            ,pegging_id			   msc_flp_supply_demand_v3.pegging_id%TYPE
                            ,plan_id               msc_flp_supply_demand_v3.plan_id%TYPE
                            ,org_id                msc_flp_supply_demand_v3.organization_id%TYPE
                            ,item_id               msc_flp_supply_demand_v3.item_id%TYPE
                            ,sr_instance_id        msc_flp_supply_demand_v3.sr_instance_id%TYPE
                            ,transaction_id        msc_flp_supply_demand_v3.transaction_id%TYPE
                           ); 
                           
	TYPE icc_tab_type       IS TABLE OF icc_type;
	TYPE temp_tab_type      IS TABLE OF xxnbty_pegging_temp_tbl%ROWTYPE;

   
   g_temp_rec              temp_tab_type := temp_tab_type(); 

   g_db_link               VARCHAR2(25);
   g_icc_db_link           VARCHAR2(25); --3/25/2015 Albert Flores
   g_instance_id		   NUMBER; --3/25/2015 Albert Flores
   g_record_ctr            NUMBER := 0;
   g_rm_index              NUMBER := 0;
   g_bl_index              NUMBER := 0;
   g_bc_index              NUMBER := 0;
   g_fg_index              NUMBER := 0;
   g_dd_index              NUMBER := 0;
   
	icc_rm_constant         CONSTANT VARCHAR2(25) := 'Raw Material';
	icc_bl_constant         CONSTANT VARCHAR2(25) := 'BLEND';
	icc_bc_constant         CONSTANT VARCHAR2(25) := 'Bulk/Component';
	icc_fg_constant         CONSTANT VARCHAR2(25) := 'Finished Product';
	icc_dd_constant         CONSTANT VARCHAR2(25) := 'Deals & Display';
	plan_id_constant		CONSTANT NUMBER 	  := -1;	--3/25/2015 Albert Flores		
    ctgry_id_constant       CONSTANT msc_orders_v.category_set_id%TYPE := 1008;
	
	--xxnbty_get_catalog_fn function
	FUNCTION xxnbty_get_catalog_fn( p_segment1 IN VARCHAR2 , p_org IN NUMBER)  RETURN VARCHAR2;
	
	--procedure that will get items with icc in EBS and insert it into the Staging table XXNBTY_CATALOG_STAGING_TBL
	PROCEDURE get_catalog_pr( errbuf	OUT VARCHAR2
							 ,retcode	OUT NUMBER);
							 
	--main procedure
	PROCEDURE main_pr( errbuf           OUT VARCHAR2
                     ,retcode           OUT NUMBER
                     ,p_plan_name       msc_orders_v.compile_designator%TYPE
                     ,p_org_code        msc_orders_v.organization_code%TYPE
                     ,p_catalog_group	VARCHAR2
                     ,p_planner_code	msc_orders_v.planner_code%TYPE
                     ,p_purchased_flag  msc_orders_v.purchasing_enabled_flag%TYPE
                     ,p_item_name		msc_orders_v.item_segments%TYPE
                     ,p_main_from_date	VARCHAR2
                     ,p_main_to_date	VARCHAR2);
	
	--procedure that will get root report
	PROCEDURE get_root_rep( errbuf             OUT VARCHAR2
                          ,retcode             OUT NUMBER
                          ,p_plan_name         msc_orders_v.compile_designator%TYPE
                          ,p_org_code          msc_orders_v.organization_code%TYPE
                          ,p_catalog_group	   VARCHAR2
                          ,p_planner_code	   msc_orders_v.planner_code%TYPE
                          ,p_purchased_flag    msc_orders_v.purchasing_enabled_flag%TYPE
                          ,p_item_name		   msc_orders_v.item_segments%TYPE
                          ,p_from_date	       msc_orders_v.new_due_date%TYPE
                          ,p_to_date		   msc_orders_v.new_due_date%TYPE);
	
   --procedure that will retrieve pegging report of root record
   PROCEDURE get_pegging_details( errbuf        OUT VARCHAR2
                                 ,retcode       OUT NUMBER
                                 ,p_pegging_rec icc_type);
   
   --procedure that will re-assign records to designated icc type
	PROCEDURE collect_rep ( errbuf   	 OUT VARCHAR2
                          ,retcode  	 OUT NUMBER
                          ,p_icc    	 icc_type);
   
   --procedure that will populate temp table
	PROCEDURE populate_temp_table( errbuf         OUT VARCHAR2
                                 ,retcode  		  OUT NUMBER
                                 ,p_temp_tab	  temp_tab_type);
                                 
  	--procedure that will generate pegging report
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
									  ,p_main_to_date	 VARCHAR2);                                              
							
END XXNBTY_MSCREP01_MULTI_PEGG_PKG;
/
show errors;
