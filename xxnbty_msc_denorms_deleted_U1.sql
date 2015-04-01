--------------------------------------------------------------------------------------------------------
/*
	Table Name: xxnbty_msc_denorms_deleted_U1																		
	Author's Name: Erwin Ramos																			
	Date written: 23-Mar-2015																							
	RICEFW Object: EXT03																								
	Description: Index for for xxnbty_msc_denorms_deleted EXT03-Safety Stocks.																
	Program Style: 																									
																													
	Maintenance History:																							
																													
	Date			Issue#		Name						Remarks																
	-----------		------		-----------					------------------------------------------------					
	23-Mar-2015		141		 	Erwin Ramos					Initial Development. Created to resolve defect#141 performance issue. 

*/			
--------------------------------------------------------------------------------------------------------

	CREATE UNIQUE INDEX
		xxnbty_msc_denorms_deleted_U1
	ON
	   xxnbty_msc_denorms_deleted
	(   demand_id 
	   ,bucket_type 
	   ,scenario_id 
	   ,sr_instance_id
	   ,sr_organization_id
	   ,sr_inventory_item_id
	 );
	   
	   