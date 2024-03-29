#A. Customer Nodes Exploration
#1. How many unique nodes are there on the Data Bank system?
select count(distinct node_id)
from customer_nodes;
#Ans:5

#2. What is the number of nodes per region?
select r.region_name, count(node_id)
from customer_nodes as c
join regions as r
on c.region_id=r.region_id
group by region_name
order by region_name;

#3. How many customers are allocated to each region?
select region_name, count(distinct customer_id)
from customer_nodes as c
join regions as r
on c.region_id=r.region_id
group by region_name
order by region_name;

#4. How many days on average are customers reallocated to a different
#node?
select avg(datediff(end_date,start_date))
from customer_nodes
where end_date != '9999-12-31';
#around 14 days on average

#B. Customer Transactions
#1. What is the unique count and total amount for each transaction type?
select txn_type, count(*), sum(txn_amount)
from customer_transactions
group by txn_type;

#2. What is the average total historical deposit counts and amounts for all
#customers?
with s1 as(
select customer_id, count(*) as number_of_deposits, avg(txn_amount) as avg_deposit_per_customer
from customer_transactions
where txn_type='deposit'
group by customer_id)

select avg(s1.number_of_deposits) as avg_number_of_deposits,
	avg(s1.avg_deposit_per_customer) as overall_avg
from s1;

#3. For each month - how many Data Bank customers make more than 1
#deposit and either 1 purchase or 1 withdrawal in a single month?
#creating three new columns named deposit, purchase and withdrawal in 1 or 0 form for each custome id
with s1 as(
select customer_id,
		extract(month from txn_date) as month,
        sum(case when txn_type='deposit' then 1 else 0 end) as deposits,
        sum(case when txn_type='purchase' then 1 else 0 end) as purchases,
        sum(case when txn_type='withdrawal' then 1 else 0 end) as withdrawals
from customer_transactions
group by customer_id, extract(month from txn_date))

#filtering for only those customers who made at least one deposit and either a purchase or withdrawal in a month
select month,
		count(*)
from s1
where deposits>1
and (purchases=1 or withdrawals=1)
group by month
order by month;

#4. What is the closing balance for each customer at the end of the month?
with s1 as(
select customer_id,
		extract(month from txn_date) as month,
		txn_type,
        txn_amount,
        case when txn_type='deposit' then 1 when txn_type='purchase' 
        then -1 else -1 end as txn_multiplier
from customer_transactions
order by customer_id,txn_date),

#Using the above CTE we will create four new columns which segregate data from the txn_amount
#column month-wise and includes the appropriate sign(+/-) with the data values.
s2 as(
select customer_id,
		 case when month=1 then txn_amount*txn_multiplier else 0 end as month_1_transaction,
		case when month=2 then txn_amount*txn_multiplier else 0 end as month_2_transaction,
		case when month=3 then txn_amount*txn_multiplier else 0 end as month_3_transaction,
		case when month=4 then txn_amount*txn_multiplier else 0 end as month_4_transaction
        from s1),
     
 #aggregation of data is performed for each customer using results from the previous CTE.
 #Four separate columns are created containing net transactions in each month for each customer
s3 as(
	select customer_id,
	sum(month_1_transaction) as month_1_net,
	sum(month_2_transaction) as month_2_net,
	sum(month_3_transaction) as month_3_net,
    sum(month_4_transaction) as month_4_net
from s2
group by customer_id
order by customer_id)

#results from the above CTE are used to calculate net balance at the end of each month
#for each customer.
select customer_id,
		month_1_net as Jan,
		month_1_net+month_2_net as Feb,
		month_1_net+month_2_net+month_3_net as Mar,
		month_1_net+month_2_net+month_3_net+month_4_net as Apr
from s3;
        
#5. What is the percentage of customers who increase their closing balance
#by more than 5%?
#using the same query from the previous question. we will only add one final step(filter) to it.
with s1 as(
select customer_id,
		extract(month from txn_date) as month,
		txn_type,
        txn_amount,
        case when txn_type='deposit' then 1 when txn_type='purchase' 
        then -1 else -1 end as txn_multiplier
from customer_transactions
order by customer_id,txn_date),

s2 as(
select customer_id,
		 case when month=1 then txn_amount*txn_multiplier else 0 end as month_1_transaction,
		case when month=2 then txn_amount*txn_multiplier else 0 end as month_2_transaction,
		case when month=3 then txn_amount*txn_multiplier else 0 end as month_3_transaction,
		case when month=4 then txn_amount*txn_multiplier else 0 end as month_4_transaction
        from s1),
     
s3 as(
	select customer_id,
	sum(month_1_transaction) as month_1_net,
	sum(month_2_transaction) as month_2_net,
	sum(month_3_transaction) as month_3_net,
    sum(month_4_transaction) as month_4_net
from s2
group by customer_id
order by customer_id),

s4 as(
		select customer_id,
		month_1_net as Jan,
        month_1_net+month_2_net as Feb,
        month_1_net+month_2_net+month_3_net as Mar,
        month_1_net+month_2_net+month_3_net+month_4_net as Apr
from s3)

#using the results from the above CTEs, a filter is applied for only those customers whose
#April balance is more than 1.05 times their Jan balance
select
		(select count(customer_id)
		from s4
		where Apr>Jan and (Apr-Jan)/Jan*100>5.0)/count(customer_id)*100 as percentage
from s4;

#C. Data Allocation Challenge
#running customer balance column that includes the impact of each
#transaction:

#first create a CTE with a column named 'change in balance'.Values in this column are assigned
#positive or negative sign based on the nature of the transaction.
with s1 as(
		select customer_id,
		txn_date,
		case when txn_type='deposit' then txn_amount
        else -txn_amount end as change_in_balance
from customer_transactions)

#the change_in_balance column from the previous step is used to calculate a running total that
#updates after every transaction by a customer:
select customer_id,
		txn_date,
		sum(change_in_balance) over(partition by customer_id order by txn_date 
        rows between unbounded preceding and current row) as running_balance
from s1;

#Calculate minimum, average and maximum values of the running balance for each
#customer
#we will use the previous query to perform min,max and avg calculations on the running balance
with s1 as(
		select customer_id,
		txn_date,
		case when txn_type='deposit' then txn_amount
        else -txn_amount end as change_in_balance
from customer_transactions),

s2 as(
		select customer_id,
		txn_date,
		sum(change_in_balance) over(partition by customer_id order by txn_date 
        rows between unbounded preceding and current row) as running_balance
from s1)

select customer_id,
		min(running_balance) as minimum,
        max(running_balance) as maximum,
        round(avg(running_balance),2) as average
from s2
group by customer_id;
-------------------------------------------------------------------
#Option1:
#data is allocated based on the ending balance of previous month.
#where a customer's ending balance is negative, data allocated is zero. 
with s1 as(
select customer_id,
		extract(month from txn_date) as month,
		txn_type,
        txn_amount,
        case when txn_type='deposit' then 1 when txn_type='purchase' 
        then -1 else -1 end as txn_multiplier
from customer_transactions
order by customer_id,txn_date),

s2 as(
select customer_id,
		 case when month=1 then txn_amount*txn_multiplier else 0 end as month_1_transaction,
		case when month=2 then txn_amount*txn_multiplier else 0 end as month_2_transaction,
		case when month=3 then txn_amount*txn_multiplier else 0 end as month_3_transaction,
		case when month=4 then txn_amount*txn_multiplier else 0 end as month_4_transaction
        from s1),
     
s3 as(
	select customer_id,
	sum(month_1_transaction) as month_1_net,
	sum(month_2_transaction) as month_2_net,
	sum(month_3_transaction) as month_3_net,
    sum(month_4_transaction) as month_4_net
from s2
group by customer_id
order by customer_id),

s4 as(
select customer_id,
		month_1_net as Jan,
		month_1_net+month_2_net as Feb,
		month_1_net+month_2_net+month_3_net as Mar,
		month_1_net+month_2_net+month_3_net+month_4_net as Apr
from s3)

select sum(case when Jan>0 then Jan else 0 end) as Feb_allocation,
		sum(case when Feb>0 then Jan else 0 end) as Mar_allocation,
        sum(case when Mar>0 then Jan else 0 end) as Apr_allocation
from s4;
#Total data allocated for Feb, Mar and Apr=542142

#Option2
#based on average amount of money kept in the account over the last 30 days
#average=(beg.bal+end bal)/2
with s1 as(
select customer_id,
		extract(month from txn_date) as month,
		txn_type,
        txn_amount,
        case when txn_type='deposit' then 1 when txn_type='purchase' 
        then -1 else -1 end as txn_multiplier
from customer_transactions
order by customer_id,txn_date),

s2 as(
select customer_id,
		 case when month=1 then txn_amount*txn_multiplier else 0 end as month_1_transaction,
		case when month=2 then txn_amount*txn_multiplier else 0 end as month_2_transaction,
		case when month=3 then txn_amount*txn_multiplier else 0 end as month_3_transaction,
		case when month=4 then txn_amount*txn_multiplier else 0 end as month_4_transaction
        from s1),
     
s3 as(
	select customer_id,
	sum(month_1_transaction) as month_1_net,
	sum(month_2_transaction) as month_2_net,
	sum(month_3_transaction) as month_3_net,
    sum(month_4_transaction) as month_4_net
from s2
group by customer_id
order by customer_id),

s4 as(
select customer_id,
		month_1_net as Jan,
		month_1_net+month_2_net as Feb,
		month_1_net+month_2_net+month_3_net as Mar,
		month_1_net+month_2_net+month_3_net+month_4_net as Apr
from s3)

select sum(case when (0+Jan)/2>0 then(0+Jan)/2 else 0 end) as Feb_allocation,
		sum(case when (Jan+Feb)/2>0 then(Jan+Feb)/2 else 0 end) as Mar_allocation,
        sum(case when (Feb+Mar)/2>0 then(Feb+Mar)/2 else 0 end) as Apr_allocation
from s4;
#Total data allocated for Feb, Mar and Apr=587393

#Option 3
#data is updated real-time
#data allocated equals the maximum value of running balance for each customer
with s1 as(
		select customer_id,
		txn_date,
		case when txn_type='deposit' then txn_amount
        else -txn_amount end as change_in_balance
from customer_transactions),

s2 as(
		select customer_id,
		txn_date,
		sum(change_in_balance) over(partition by customer_id order by txn_date 
        rows between unbounded preceding and current row) as running_balance
from s1),

s3 as(
		select customer_id,
		min(running_balance) as minimum,
        max(running_balance) as maximum,
        round(avg(running_balance),2) as average
from s2
group by customer_id)

select sum(maximum)
from s3;
#Total data allocated for Feb, Mar and Apr=622320
#Choose option 1. Needs least amount of data.
