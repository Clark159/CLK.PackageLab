maven-resolve-packages  : 解析套件
maven-fetch-packages    : 下載套件
maven-build-application : 編譯程式

nuget-resolve-packages  : 解析套件
nuget-fetch-packages    : 下載套件
nuget-build-application : 編譯程式

npm-resolve-packages  : 解析套件
npm-fetch-packages    : 下載套件
npm-build-application : 編譯程式


	<parent>
      <groupId>com.example</groupId>
      <artifactId>demo-lock</artifactId>
      <version>4.0.0</version>
      <relativePath>./packages-lock.xml</relativePath>
    </parent>