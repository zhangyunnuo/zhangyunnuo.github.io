#include <bits/stdc++.h>
#include <cmath>
using namespace std;

struct student{
	int xh;
	int cj;
}; 
bool cmp(student a,student b){
	if (a.cj > b.cj){
		return 1;
	}
	else if (a.cj == b.cj){
		if (a.xh < b.xh){
			return 1;
		}
	}
	return 0;
}
int main(){
	int n,m;
	cin >> n >> m;
	m = floor(m * 1.5);
	student a[n+5];
	for (int i = 1;i <= n;i++){
		cin >> a[i].xh >> a[i].cj;
	}
	sort(a+1,a+n+1,cmp);
	cout << a[m].cj << " ";
	int scort = a[m].cj , xh_b = 0;
	int i = 1;
	while (scort <= a[i].cj){
		xh_b ++;
		i++;
	}
	cout << xh_b << endl;
	for (int j = 1;j <= xh_b;j++){
		cout << a[j].xh << " " << a[j].cj << endl;
	}
	return 0;
}
