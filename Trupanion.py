import pandas as pd
from datetime import datetime
from lightgbm import LGBMClassifier, LGBMRegressor
from sklearn.model_selection import GridSearchCV, RandomizedSearchCV
import matplotlib.pyplot as plt
import seaborn as sns
from sklearn.metrics import r2_score
import shap
from sklearn.metrics import mean_squared_error
from math import sqrt

#Import Data
df=pd.read_csv('C:/Trupanion/MonthsPetData.txt',sep='\t',parse_dates=['MinDate'])

df['ClaimAmount']=df['ClaimAmount'].fillna(0)
df['ClaimAmountPast']=df['ClaimAmountPast'].fillna(0)
df['ClaimAmountPastMonth']=df['ClaimAmountPastMonth'].fillna(0)
df['ClaimAmountPastYear']=df['ClaimAmountPastYear'].fillna(0)
df['ClaimAmountAverage']=df['ClaimAmountAverage'].fillna(0)
df['DaysInPolicy']=df['DaysInPolicy'].fillna(0)

#Split Data into X and Y
filter_col = [col for col in df if col.startswith('ClaimAmount')]
filter_col.remove('ClaimAmount')
X1=df[['MonthNumber','MonthYear','MinDate','TotalDays','DaysInPolicy','Species','Breed','AgeAtEnroll','MinAgeInDays','MaxAgeInDays','TotalDaysInPolicy']]
X2=df[filter_col]
XCombined = X1.join(X2)

X = pd.get_dummies(XCombined, prefix_sep="_", columns=['Breed','Species','AgeAtEnroll'])

y=df[['MinDate','ClaimAmount']]

#Note, test on previous year for accuracy
date=pd.Timestamp(2018,7,1)
X_train=X.loc[X['MinDate']<date]
y_train=y.loc[y['MinDate']<date]

X_test=X.loc[X['MinDate']==date]
y_test=y.loc[y['MinDate']==date]

X_train.drop('MinDate',axis='columns',inplace=True)
y_train.drop('MinDate',axis='columns',inplace=True)
X_test.drop('MinDate',axis='columns',inplace=True)
y_test.drop('MinDate',axis='columns',inplace=True)

#Uses Randomized Search CV to tune parameters
gridParams = {
    'max_depth': [4,8,16],
    'min_child_samples': [10,20],
    'learning_rate': [0.005,0.01],
    'n_estimators': [40],
    'num_leaves': [16,32],
    'boosting_type' : ['gbdt'],
    'colsample_bytree' : [0.6, 0.65, 0.7],
    'subsample' : [0.7,0.75],
    'reg_alpha' : [1,1.2],
    'reg_lambda' : [1,1.2,1.4]
    }

#Run RandomizedSearch CV
regressor = LGBMRegressor()

grid = RandomizedSearchCV(regressor, gridParams,
                    verbose=0,
                    cv=5,
                    n_jobs=8,
                    n_iter=50)

grid.fit(X_train, y_train)

# Print the best parameters found
print(grid.best_params_)
print(grid.best_score_)

#Use best params
regressor = LGBMRegressor(**grid.best_params_)

regressor.fit(X=X_train,y=y_train) #training the algorithm

y_pred = regressor.predict(X_test)

print(r2_score(y_test,y_pred))#0.01
print(sqrt(mean_squared_error(y_test, y_pred)))

y_test['ClaimAmountAvg']=y_test.mean().values[0]

print(sqrt(mean_squared_error(y_test['ClaimAmount'], y_test_mean['ClaimAmountAvg'])))

print(y_test.sum())
print(y_pred.sum())

#Use shap to plot LGBM Model
explainer = shap.TreeExplainer(regressor)
shap_values = explainer.shap_values(X_test)
shap.summary_plot(shap_values, X_test, plot_type="bar")