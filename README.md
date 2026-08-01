# CLK.PackageLab

套件管理工具集，提供 Maven、NPM、NuGet、PyPI 套件的計算與下載腳本。

---

## 套件計算腳本 (Maven / NPM / NuGet / PyPI)

### 功能說明

從套件引用檔解析所有相依套件（含遞移相依），並產生以下輸出檔案：

| 檔案 | 說明 |
|------|------|
| `package-all.txt` | 所有相依套件的完整清單（含版本） |
| `package-lock.*` | 相依套件的鎖定清單（**Maven** 用 `.xml`，**NPM / NuGet** 用 `.json`） |
| `package-adding.txt` | **需要新套件審查**的套件清單 |
| `package-updating.txt` | **需要升級套件版本**的套件清單 |

### 腳本清單

| 類型   | PowerShell | Batch |
|--------|-----------|-------|
| Maven  | [Maven/maven-resolve-packages.ps1](Maven/maven-resolve-packages.ps1) | [Maven/maven-resolve-packages.bat](Maven/maven-resolve-packages.bat) |
| NPM    | [NPM/npm-resolve-packages.ps1](NPM/npm-resolve-packages.ps1) | [NPM/npm-resolve-packages.bat](NPM/npm-resolve-packages.bat) |
| NuGet  | [NuGet/nuget-resolve-packages.ps1](NuGet/nuget-resolve-packages.ps1) | [NuGet/nuget-resolve-packages.bat](NuGet/nuget-resolve-packages.bat) |
| PyPI   | [PyPI/pypi-resolve-packages.ps1](PyPI/pypi-resolve-packages.ps1) | [PyPI/pypi-resolve-packages.bat](PyPI/pypi-resolve-packages.bat) |

### 操作說明

1. 建立一個空資料夾，將腳本與套件引用檔一同放入。

   目錄結構範例：
   ```
   my-folder/
   ├── pom.xml                        ← Maven 套件引用檔
   ├── maven-resolve-packages.bat
   ├── package.json                   ← NPM 套件引用檔
   ├── npm-resolve-packages.bat
   ├── package.csproj                 ← NuGet 套件引用檔
   ├── nuget-resolve-packages.bat
   ├── requirements.txt                ← PyPI 套件引用檔
   └── pypi-resolve-packages.bat
   ```

2. 執行腳本：

   ```batch
   :: Maven
   maven-resolve-packages.bat

   :: NPM
   npm-resolve-packages.bat

   :: NuGet
   nuget-resolve-packages.bat

   :: PyPI
   pypi-resolve-packages.bat
   ```

3. 腳本執行中，看到下列畫面，代表執行完畢：

   <!-- 截圖 -->

4. 執行完成後，確認 `package-all.txt`、`package-lock.*`、`package-adding.txt`、`package-missing.txt` 已產生。

---

## 套件下載腳本 (Maven / NPM / NuGet / PyPI)

### 功能說明

根據 `package.txt` 清單，從來源 Registry 下載套件，並產生以下輸出資料夾：

| 資料夾 | 說明 |
|--------|------|
| `packages/` | 所有下載的套件檔案 |

### 腳本清單

| 類型   | PowerShell | Batch |
|--------|-----------|-------|
| Maven  | [Maven/maven-fetch-packages.ps1](Maven/maven-fetch-packages.ps1) | [Maven/maven-fetch-packages.bat](Maven/maven-fetch-packages.bat) |
| NPM    | [NPM/npm-fetch-packages.ps1](NPM/npm-fetch-packages.ps1) | [NPM/npm-fetch-packages.bat](NPM/npm-fetch-packages.bat) |
| NuGet  | [NuGet/nuget-fetch-packages.ps1](NuGet/nuget-fetch-packages.ps1) | [NuGet/nuget-fetch-packages.bat](NuGet/nuget-fetch-packages.bat) |
| PyPI   | [PyPI/pypi-fetch-packages.ps1](PyPI/pypi-fetch-packages.ps1) | [PyPI/pypi-fetch-packages.bat](PyPI/pypi-fetch-packages.bat) |

### 操作說明

> **注意：下載腳本必須放在需求單資料夾內才能正確執行。**
>
> 資料夾名稱格式：`XXXXXXXXXXXX-XX`（12 位數字 + 連字號 + 2 位數字）
>
> 範例：`202406240001-01`

1. 在需求單資料夾中建立對應的子資料夾，並將腳本與 `package.txt` 一同放入。

   目錄結構範例：
   ```
   202406240001-01/
   ├── package.txt
   ├── maven-fetch-packages.ps1
   ├── maven-fetch-packages.bat
   ```

2. 確認 `package.txt` 存在，格式依生態系不同：

   | 類型   | 格式 | 範例 |
   |--------|------|------|
   | Maven  | `groupId:artifactId:version` | `org.springframework:spring-core:6.1.0` |
   | NPM    | `name@version` | `lodash@4.17.21` |
   | NuGet  | `name/version` | `Newtonsoft.Json/13.0.3` |
   | PyPI   | `name==version` | `requests==2.31.0` |

3. 執行腳本：

   ```batch
   :: Maven
   maven-fetch-packages.bat

   :: NPM
   npm-fetch-packages.bat

   :: NuGet
   nuget-fetch-packages.bat

   :: PyPI
   pypi-fetch-packages.bat
   ```

4. 執行腳本後，看到下列畫面，代表執行完畢：

   <!-- 截圖 -->

5. 執行完成後，確認 `packages/` 資料夾已產生，內含所有套件檔案。

   <!-- 截圖 -->
