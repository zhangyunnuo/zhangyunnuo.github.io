#include<iostream>
using namespace std;

int main(){ 
    int n,m,a[105][105];
    cin >> n >> m;
    for(int i = 1;i <= n;i++){
		for(int j = 1;j <= m;j++){
    		cin >> a[i][j];
		}	
	}
	for(int i = 1;i <= n;i++){
		for(int j = m;j >= 1;j--){
    		cout << a[j][i] <<" ";
		}	
		cout << endl;
	}
    return 0;
}

