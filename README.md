# CLK.PackageLab

## Maven

### 操作流程

```
packages.txt  →  maven-resolve-packages  →  packages-lock.txt
                                         →  packages-lock.xml
                                         →  pom.xml

packages-lock.txt  →  maven-fetch-packages  →  packages/
packages-lock.xml  →
pom.xml            →
```

### 步驟一：編輯套件清單

編輯 [Maven/packages.txt](Maven/packages.txt)，每行一個套件，格式如下：

```
groupId:artifactId:version
```

範例：

```
org.apache.httpcomponents.client5:httpclient5:5.3
```

### 步驟二：解析套件相依

執行 [Maven/maven-resolve-packages.bat](Maven/maven-resolve-packages.bat)。

此步驟會依據 `packages.txt` 解析完整的相依樹，並產生以下三個檔案：

| 檔案 | 說明 |
|------|------|
| `pom.xml` | Maven 專案描述，包含所有直接相依 |
| `packages-lock.txt` | 鎖定所有相依（含遞移）的版本清單 |
| `packages-lock.xml` | 鎖定版本的 BOM（Bill of Materials） |

### 步驟三：下載套件

執行 [Maven/maven-fetch-packages.bat](Maven/maven-fetch-packages.bat)。

此步驟會依據前一步產生的鎖定檔，從 Maven Central 下載所有套件（含遞移相依）至 `Maven/packages/` 目錄。

### 注意事項

- 執行前須確認系統已安裝 `mvn` 並加入 PATH。
- `maven-resolve-packages` 需連線至 Maven Central 解析相依樹。
- `maven-fetch-packages` 執行前必須先完成 `maven-resolve-packages`，確保 `pom.xml`、`packages-lock.txt`、`packages-lock.xml` 均存在。
- 每次執行 `maven-fetch-packages` 時，`packages/` 和 `.m2/` 目錄都會被清除重建。