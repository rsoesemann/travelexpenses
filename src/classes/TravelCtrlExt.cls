global with sharing class TravelCtrlExt {
    
    private final Travel__c travel;
    private ApexPages.StandardController stdCtrl;
    private List<Expense__c> sortedExpenses = new List<Expense__c>();
    private List<Expense__c> dailyExpenses = new List<Expense__c>();
      
  
    // CONSTRUCTOR
    
    public TravelCtrlExt(ApexPages.StandardController standardController) {
        stdCtrl = standardController;
        
        travel = [SELECT Id, Name, CurrencyIsoCode, txt_Reason__c, txa_Description__c, 
                         dtm_Start__c, dtm_End__c, Owner.FirstName, Owner.LastName, 
                         rsum_TotalExpenses__c, rsum_ReimbursableExpenses__c, rsum_PerDiems__c, 
                         fcur_Reimbursement__c
                  FROM Travel__c
                  WHERE Id = :stdCtrl.getId()];         
    }
    
    
    //GLOBAL METHODS
    
    @RemoteAction
    global static String getRecordStatus(Id recordId) {
        String result = '';
        List<ProcessInstance> processes = [SELECT Id, Status, CreatedDate 
                                           FROM ProcessInstance 
                                           WHERE TargetObjectId = :recordId];
        if(processes.size() > 0) {
            ProcessInstance processinstance = processes[0];
            for(ProcessInstance p : processes) {
                if(p.CreatedDate > processinstance.CreatedDate) {
                    processinstance = p;
                }
            }
            result = processinstance.Status;
        }
    
        return result;
    }
    

    // PUBLIC METHODS
    
    public List<Expense__c> getSortedExpenses() {
        return sortedExpenses;
    }
    
    
    public List<Expense__c> getDailyExpenses() {
        return dailyExpenses; 
    }
    
    public List<Expense__c> getExpensesGroupedByDate() {
    	List<Expense__c> result = new List<Expense__c>();
    	
    	Expense__c expense = sortedExpenses[0];
    	Expense__c emptyExpense = new Expense__c();
    	for(Expense__c e : sortedExpenses) {
    		if(e.dat_ExpenseDate__c != expense.dat_ExpenseDate__c) {
    			result.add(emptyExpense);
    			expense = e;	
    		}
    		result.add(e);
    	}
    
    	return result;
    }
    
    
    public String getOwner() {
        String result = travel.Owner.FirstName + ' ' + travel.Owner.LastName;
        
        return result;
    }
    
    
    public Decimal getTotalExpenses() {
        Decimal result = travel.rsum_TotalExpenses__c.setScale(2);
        
        return result;
    }
    
    
    public Decimal getReimbursableExpenses() {
        Decimal result = travel.rsum_ReimbursableExpenses__c.setScale(2);
        
        return result;
    } 
    
    
    public Decimal getTotalPerDiems() {
        Decimal result = travel.rsum_PerDiems__c.setScale(2);
        
        return result;
    }
    
    
    public Decimal getTotalReimbursement() {
        Decimal result = travel.fcur_Reimbursement__c.setScale(2);
        
        return result;
    }
    
    
    public List<DailySummaryRow> getDailySummaries() {
        List<DailySummaryRow> result = generateDailySummaries();
        
        return result;
    }
    
    
    public String getTravelId() {
        return travel.Id;
    }
    
    
    public String getRelatedListId() {
        String result = CustomSettings__c.getAll().values().get(0).txt_TravelExpenseRelationId__c;

        return result;
    }
    
    
    public void doGeneratePerDiemsAndLists() {
        doGeneratePerDiems();
        doInitializeLists();
    }
    
    public PageReference doGeneratePerDiemsAndRedirect() {
        PageReference result = stdCtrl.view();
        
        doGeneratePerDiems();
        
        return result;       
    }
    
    
    public void doInitializeLists() {
        sortExpenses();
        calculateDailyExpenses();
    }


    public void doGeneratePerDiems() {
        PerDiemCalculator perDiemCalculator = new PerDiemCalculator(travel);
    	perDiemCalculator.calculate();
    }
    
    
    public PageReference doRedirectToTravel() {
        PageReference result = stdCtrl.view();

        return result;
    }
    
    
    public PageReference doValidateOnSubmit() {
        PageReference result;
        
        checkIfTravelIsLocked();
        
        RuleValidator validator = new RuleValidator(RuleType.SubmitTravelRule);
        validator.validate(new List<SObject>{ travel });
        
        if(!ApexPages.hasMessages()) {
            result = new PageReference('/apex/travelSubmit?id='+travel.Id);  
            result.setRedirect(true);  
        }
        else {
            result = null;
        }
        
        return result;
    }
    

    public PageReference doGenerateTravelExpenseReport() {
        PageReference result = new PageReference('/apex/travelExpenseReport?id='+travel.Id);
        result.setRedirect(true);
        
        return result;   
    }
    
    
    public PageReference doRedirectMobileDevices() {
        PageReference result = null;
        
        Boolean isMobileDevice = false;
        if( ApexPages.currentPage().getParameters().get('sfdcIFrameHost') !=null 
            || ApexPages.currentPage().getParameters().get('sfdcIFrameOrigin') !=null
            || ApexPages.currentPage().getParameters().get('isdtp') == 'p1'
            || ( ApexPages.currentPage().getParameters().get('retURL') != null && ApexPages.currentPage().getParameters().get('retURL').contains('projectone') ) ) {
            
            isMobileDevice = true;
        }
        
        if( isMobileDevice ) {
            result = new PageReference('/apex/travelViewMobile?id={!travelid}');          
        }
        
        return result;
    }
    
    
    // PRIVATE METHODS
    
    private void checkIfTravelIsLocked() {
        Savepoint sp = Database.setSavepoint();

        try {
            update travel;
        }
        catch(DMLException ex) {
            if(ex.getMessage().contains('ENTITY_IS_LOCKED')) {
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'Travel is locked for approval.'));
            }
        }
        
        Database.rollback(sp);
    }
    
    
    private void sortExpenses() {
        sortedExpenses = [SELECT Id, Name, RecordType.Name, cur_Amount__c, dtm_DepartureTime__c, 
                                 dtm_ArrivalTime__c, dat_CheckInDate__c, dat_CheckOutDate__c, 
                                 lkp_Location__c, CurrencyIsoCode, dat_ExpenseDate__c, mdr_Travel__c, 
                                 pkl_Reimbursement__c,cur_OriginalAmount__c,
                                 lkp_Location__r.cur_FullDailyRate__c,
                                 lkp_MealInvitation__r.lkp_Breakfast__c,lkp_MealInvitation__r.lkp_Breakfast__r.pct_FullDayAllowanceRate__c,
                                 lkp_MealInvitation__r.lkp_Lunch__c,lkp_MealInvitation__r.lkp_Lunch__r.pct_FullDayAllowanceRate__c,
                                 lkp_MealInvitation__r.lkp_Dinner__c,lkp_MealInvitation__r.lkp_Dinner__r.pct_FullDayAllowanceRate__c
                          FROM Expense__c
                          WHERE mdr_Travel__c = :travel.Id
                          ORDER BY dat_ExpenseDate__c ASC, dtm_DepartureTime__c ASC, RecordType.Name ASC];
    }

    
    private void calculateDailyExpenses() {
        Map<Date, Decimal> expensePerDate = new Map<Date, Decimal>();
        
        for(AggregateResult ar : [SELECT dat_ExpenseDate__c tag, SUM(cur_Amount__c) summe 
                                  FROM Expense__c
                                  WHERE mdr_Travel__c = :stdCtrl.getId()
                                  GROUP BY dat_ExpenseDate__c]) {
            Date tag = (Date) ar.get('tag');
            Decimal summe = (Decimal) ar.get('summe');
            expensePerDate.put(tag, summe);
        }
                
        List<Date> dates= new List<Date>(); 
        for(Date d : expensePerDate.keySet()) {
            dates.add(d);
        }
        dates.sort();
        
        List<CurrencyType> currencyTypeEur = [SELECT ConversionRate
                                              FROM CurrencyType
                                              WHERE IsoCode = 'EUR'];
        Decimal currencyRateEur = currencyTypeEur[0].ConversionRate;
        
        Expense__c e;
        for(Date d : dates) {
            Decimal amountInEuro = expensePerDate.get(d) * currencyRateEur;
            e = new Expense__c(cur_Amount__c = amountInEuro, dat_ExpenseDate__c = d, CurrencyIsoCode = 'EUR');
            dailyExpenses.add(e);
        }       
    }
    
    
    private Map<Date, Decimal> calculateAmounts(Boolean justReimburseableAmounts) {
        Map<Date, Decimal> result = new Map<Date, Decimal>();
        
        List<CurrencyType> currencyTypeEur = [SELECT ConversionRate
                                              FROM CurrencyType
                                              WHERE IsoCode = 'EUR'];
        Decimal currencyRateEur = currencyTypeEur[0].ConversionRate;
        
        if(justReimburseableAmounts) {
            for(AggregateResult ar : [SELECT dat_ExpenseDate__c tag, SUM(cur_Amount__c) summe 
                                      FROM Expense__c
                                      WHERE mdr_Travel__c = :stdCtrl.getId()
                                      AND pkl_Reimbursement__c = 'I paid for this, please reimburse me.'
                                      GROUP BY dat_ExpenseDate__c]) {
                Date tag = (Date) ar.get('tag');
                Decimal summe = ( (Decimal) ar.get('summe') );
                summe = ( summe * currencyRateEur ).setScale(2);
                
                result.put(tag, summe);
            }
        }
        else {
            for(AggregateResult ar : [SELECT dat_ExpenseDate__c tag, SUM(cur_Amount__c) summe 
                                      FROM Expense__c
                                      WHERE mdr_Travel__c = :stdCtrl.getId()
                                      GROUP BY dat_ExpenseDate__c]) {
                Date tag = (Date) ar.get('tag');
                Decimal summe = ( (Decimal) ar.get('summe') );
                summe = ( summe * currencyRateEur ).setScale(2);

                result.put(tag, summe);
            }
        }   
        
        return result;
    }
    
    
    private List<DailySummaryRow> generateDailySummaries() {
        List<DailySummaryRow> result = new List<DailySummaryRow>();
                
        Set<Date> uniqueDays = new Set<Date>();
        List<Date> sortedDays = new List<Date>();
        List<DailySummaryElement> dailySummary;
        Decimal amount;
        Decimal reimbursableAmount;
        Map<Date, Decimal> dailyExpenseAmounts = calculateAmounts(false);
        Map<Date, Decimal> dailyReimbursableAmounts = calculateAmounts(true);
      
        for(Expense__c expense : sortedExpenses) {
            uniqueDays.add(expense.dat_ExpenseDate__c);
        }
        
        sortedDays.addAll(uniqueDays);
        sortedDays.sort();
        
        DailySummaryElement element;
        DailySummaryElement temp;

        for(Date d : sortedDays) {
            dailySummary = new List<DailySummaryElement>();
            
            amount = dailyExpenseAmounts.get(d);
            if( amount == null ) {
                amount = 0.00;
            } 
            
            reimbursableAmount = dailyReimbursableAmounts.get(d);
            if( reimbursableAmount == null ) {
                reimbursableAmount = 0.00;
            } 
           
            for(Expense__c e : sortedExpenses) {
                if((Date) e.dat_ExpenseDate__c == d) {
                        
                        element = new DailySummaryElement(e.RecordType.Name, e.cur_Amount__c, e.CurrencyIsoCode);

                        if(e.pkl_Reimbursement__c.equals('I paid for this, please reimburse me.')) {
                                element.reimbursable = true;
                        }
                        else {
                                element.reimbursable = false;
                        }
                    
                    if (ExpenseType.isPerDiem(e) 
                        && (e.lkp_MealInvitation__r.lkp_Breakfast__c != null 
                        || e.lkp_MealInvitation__r.lkp_Lunch__c != null 
                        || e.lkp_MealInvitation__r.lkp_Dinner__c != null)) {
                                     
                        temp = new DailySummaryElement('Per Diem vor Kürzungen', e.cur_OriginalAmount__c, e.CurrencyIsoCode,true);
                        dailySummary.add(temp);
                        
                        if(e.lkp_MealInvitation__r.lkp_Breakfast__c != null) {
                            temp = new DailySummaryElement('> Gekürzt für Frühstück',
                                                           e.lkp_MealInvitation__r.lkp_Breakfast__r.pct_FullDayAllowanceRate__c *
                                                           e.lkp_Location__r.cur_FullDailyRate__c /100,
                                                           e.CurrencyIsoCode,true);
                            dailySummary.add(temp);
                        }
                        if(e.lkp_MealInvitation__r.lkp_Lunch__c != null) {
                            temp = new DailySummaryElement('> Gekürzt für Mittagessen',
                                                           e.lkp_MealInvitation__r.lkp_Lunch__r.pct_FullDayAllowanceRate__c *
                                                           e.lkp_Location__r.cur_FullDailyRate__c / 100,
                                                           e.CurrencyIsoCode,true);
                            dailySummary.add(temp);
                        }
                        if(e.lkp_MealInvitation__r.lkp_Dinner__c != null) {
                            temp = new DailySummaryElement('> Gekürzt für Abendessen',
                                                           e.lkp_MealInvitation__r.lkp_Dinner__r.pct_FullDayAllowanceRate__c *
                                                           e.lkp_Location__r.cur_FullDailyRate__c /100,
                                                           e.CurrencyIsoCode,true);
                            dailySummary.add(temp);
                        }
                        element.name = 'Per Diem nach Kürzungen';
                    }
                    dailySummary.add(element);
                }
            }
            DailySummaryRow row = new DailySummaryRow(d, dailySummary, amount, reimbursableAmount);
            result.add(row);
        }
       
        return result;
    }
    
    
    // INNER CLASSES
    
    public class DailySummaryRow {
        public String day { get; private set; }
        public List<DailySummaryElement> expenses { get; private set; }
        public Decimal amount { get; private set; }
        public Decimal reimbursableAmount { get; private set; }
        
        public DailySummaryRow(Date day, List<DailySummaryElement> expenses, Decimal amount, Decimal reimbursableAmount) {
            this.day = day.format();
            this.expenses = expenses;
            this.amount = amount;
            this.reimbursableAmount = reimbursableAmount;
        }
    }
    
    
    public class DailySummaryElement {
        public String name{ get; private set; }
        public Decimal amount {get; private set; }
        public Boolean reimbursable {get; private set; }
        public String elementCurrency { get; private set; }
        public Boolean isDeduction { get; private set;}
        
        public DailySummaryElement(String name, Decimal amount, String elementCurrency) {
                this.name = name;
                this.amount = amount;
                this.elementCurrency = elementCurrency;   
        }
        
        public DailySummaryElement(String name, Decimal amount, String elementCurrency, Boolean isDeduction) {
                this.name = name;
                this.amount = amount;
                this.elementCurrency = elementCurrency; 
                this.isDeduction = isDeduction;  
        }
    }
}