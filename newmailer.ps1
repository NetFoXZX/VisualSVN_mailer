param(
    #get parametrs from hook 
    [string]$Revision, # = "58", #RevisionObj number %2 
    [string]$RepPath 
 
)
Enum VerbType {
    AddFile = 0
    AddDir = 1
    ModifyFile = 2
    ReplaceFile = 3
    DeleteFile = 4
    DeleteDir = 5
}

class PathReciverClass {
    [string]$Path;
    [System.Collections.Generic.List[string]]$EMails;

    PathReciverClass([string]$Path, [System.Collections.Generic.List[string]]$Mails) {
        $this.Path = $Path;
        $this.EMails = $Mails;
    }
} #class


class ChangePathClass {
    [string]$Path;
    [VerbType]$Verb;

    ChangePathClass([string]$Path, [VerbType]$Verb) {
        $this.Path = $Path;
        $this.Verb = $Verb;
    }
    # [System.Collections.Generic.List[string]]$Mails;
} #class




class RevisionClass {
    [string]$RepositoryName;
    [string]$RepositoryPath;
    [string]$Author;
    [string]$AuthorMailAddress;
    [string]$Description;
    [int]$RevisionNumber;
    [string]$DBFormat;
    [string]$RevisionLoclaPath;
    [System.Collections.Generic.List[ChangePathClass]]$ChangePaths;
    [string]$DataPath;
    
    RevisionClass([string]$RepositoryPath, [int]$RevisionNumber) { #Constructor
        $this.SetupRevision($RepositoryPath, $RevisionNumber)
    }

    hidden [void]SetupRevision([string]$RepositoryPath, [int]$RevisionNumber) {
        $this.RevisionNumber = $RevisionNumber
        $this.RepositoryPath = $RepositoryPath
        
        $this.DataPath = $this.GetDataPath()

        $this.RepositoryName = $this.GetRepositoryName()
        $this.DBFormat = $this.GetDBFormat()
        $this.RevisionLoclaPath = $this.GetRevisionPath()
        
        $this.SetAuthorAndDescription()
        $this.ChangePaths = New-Object System.Collections.Generic.List[ChangePathClass]

        

        $this.AuthorMailAddress = $this.GetMailFromName()
        $this.SetChangePaths()
    }

    [string]GetDataPath() {
        [string]$Result = "\db\"
        [string]$FSType = ""
        [string]$Path = $this.RepositoryPath + "\db\fs-type"
        try {
            
            $FSType = Get-Content $Path -ErrorAction Stop
        }
        catch {
            Write-Host "Не найден файл: $Path" -ForegroundColor Red
        }
        if ($FSType -eq "vdfs") {
            $Result = "\db\data\"
        }

        return $Result
    }

    [string] GetRepositoryName() {
        #Get name from full path
        $TPath = $this.RepositoryPath.Split([System.IO.Path]::DirectorySeparatorChar) #form path to Name
        [string] $Result = $TPath[$TPath.Length - 1]
        return $Result
    }

    [string] GetDBFormat() {
        #Get database format  from file format
        [string]$Path = $this.RepositoryPath + $this.DataPath + "format"
        [string]$FormatContent = ""
        try { 
            $FormatContent = Get-Content $Path -ErrorAction Stop
        }
        catch {
            Write-Host "Не найден файл: $Path" -ForegroundColor Red
        }
        [string]$Result = ""
        if ($FormatContent -like "*layout linear*") {
            $Result = "linear"
        }
        else {
            [string]$div = $FormatContent.Split(" ")[3].ToString()
            $Result = $div
        }
        return $Result
    }
   
    [string] GetRevisionPath() {
        #get full path to revs
        if ($this.DBFormat -eq "linear") {
            return ""
        }
        
        [int]$Res = $null
        
        $Res = [math]::Truncate($this.RevisionNumber / $this.DBFormat)
        $RevNum = $Res.ToString() + "\"
        
        return $RevNum
    }

    [void] SetAuthorAndDescription() {
        [string]$Path = $this.RepositoryPath + $this.DataPath + "revprops\" + $this.RevisionLoclaPath + $this.RevisionNumber
        $Content = "" 
        try {
            $Content = Get-Content -path $Path -Encoding UTF8 -ErrorAction Stop
        }
        catch {
            Write-Host "Не найден файл: $Path" -ForegroundColor Red
        }
        
        $this.Author = $Content[3]
        $this.Description = $Content[$Content.Length - 2]
    }
    
    [string] GetMailFromName() {
        [System.DirectoryServices.DirectorySearcher]$Searcher = [System.DirectoryServices.DirectorySearcher]::new()
        $Searcher.Filter = "(&(objectClass=user)(SamAccountName=" + $this.Author + "))"
        $Searcher.PropertiesToLoad.Add("mail")
        
        $Users = $Searcher.FindAll()
        [string]$Result = $Users.Properties.Item("mail")
        return $Result
    }

    [void] SetChangePaths() {
        [string]$ContentPath = $this.RepositoryPath + $this.DataPath + "revs\" + $this.RevisionLoclaPath + $this.RevisionNumber
        
        $FilesContent = ""
        try {
            $FilesContent = Get-Content -Path $ContentPath -Encoding UTF8 -ErrorAction Stop
        }
        catch {
            Write-Host "Не найден файл: $ContentPath " -ForegroundColor Red
        }

        $Verb = $FilesContent | Select-String -Pattern " Add-file " -AllMatches
        if ($Verb) {
            $this.GetFileList($Verb, [VerbType]::AddFile)
        }
        
        $Verb = $FilesContent | Select-String -Pattern " Add-dir " -AllMatches
        if ($Verb) {
            $this.GetFileList($Verb, [VerbType]::AddDir)
        }
        
        $Verb = $FilesContent | Select-String -Pattern " Modify-file " -AllMatches
        if ($Verb) {
            $this.GetFileList($Verb, [VerbType]::ModifyFile)
        }
        
        $Verb = $FilesContent | Select-String -Pattern " replace-file " -AllMatches
        if ($Verb) {
            $this.GetFileList($Verb, [VerbType]::ReplaceFile)
        }
        
        $Verb = $FilesContent | Select-String -Pattern " Delete-dir " -AllMatches
        if ($Verb) {
            $this.GetFileList($Verb, [VerbType]::DeleteDir)
        }

        $Verb = $FilesContent | Select-String -Pattern " Delete-file " -AllMatches
        if ($Verb) {
            $this.GetFileList($Verb, [VerbType]::DeleteFile)
        }
        #Write-Host $this.ChangePaths[0].Path
    }

    [void] GetFileList($Content, [VerbType]$Verb) {
        #Get file list from content
        [string]$FullStr = ""
        foreach ($FullStr in $Content) {
            [int]$i = $FullStr.IndexOf(" /")
            $Res = $FullStr.Substring($i + 1)
            
            [ChangePathClass]$ResPath = [ChangePathClass]::New($Res, $Verb);
            $this.ChangePaths.Add($ResPath)
        }   #Content
        #  Write-Host $this.ChangePaths[0].Path
    }
}



class MailerSettings {
    [string]$PathToJSON;
    $AllSettings;
    [string]$RepositoryName;
    [System.Collections.Generic.List[PathReciverClass]]$PathReciver;

    MailerSettings($RepositoryName) {
        #$this.PathToJSON = $PSScriptRoot + "\mailersettings.json";
        $this.PathToJSON = $PSScriptRoot + "\rp.json";
        $this.RepositoryName = $RepositoryName;
        
       

        $this.ReadSettings();
        
        $this.PathReciver = [System.Collections.Generic.List[PathReciverClass]]::new()
        $this.SetPathsNew();
    }

    [void]ReadSettings() {
        
        try {
            $Result = Get-Content -Path $this.PathToJSON -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            $this.AllSettings = $Result
        }
        catch {
            Write-Host "Не найден файл: $($this.PathToJSON)" -ForegroundColor Red
        }
    }

    [void]SetPathsNew() {
        $repo = $this.AllSettings | Where-Object { $_.RepoName -eq $this.RepositoryName }
        
        foreach ($Item in $repo.PathsRecivers) {
            [PathReciverClass]$PRItme = [PathReciverClass]::new($Item.Path, $Item.Mail)
            $this.PathReciver.Add($PRItme)
        }
    }
} 
  

class SenderServerClass {
    [string]$ServerName = "localhost";
    [string]$FQDNServerName = "localhost";


    SenderServerClass([RevisionClass]$RevisionObj) {
        $this.ServerName = $env:COMPUTERNAME 
        $this.FQDNServerName = [System.Net.Dns]::GetHostByName(($this.ServerName)).HostName
    }


    Send([string]$MessageBody, [RevisionClass]$RevisionObj, [System.Collections.Generic.List[string]]$EmailAddresses) {

        $username = "domain\user"
        $password = "password"
        $mailservername = "mail.domain"
        $port = 9925

        [Net.Mail.SmtpClient]$SMTP = New-Object Net.Mail.SmtpClient($mailservername, $port)

        $SMTP.Credentials = New-Object System.Net.NetworkCredential($username, $password)
        $SMTP.EnableSsl = $true
        
        [string]$SMTPFrom = $this.ServerName + "@mail.domain"
        
        [string]$Subject = $RevisionObj.RepositoryName + ": " + $RevisionObj.Author + ": r" + $RevisionObj.RevisionNumber
        [System.Net.Mail.MailMessage]$message = [System.Net.Mail.MailMessage]::new()
        $message.From = $SMTPFrom
        $message.IsBodyHTML = $true

        $message.Subject = $Subject
        
        $message.Body = $messagebody 

        [System.Net.Mail.AlternateView]$view = [System.Net.Mail.AlternateView]::CreateAlternateViewFromString($messagebody, $null, "text/html")
        $message.AlternateViews.Add($view)

        $message.ReplyToList.Add($RevisionObj.AuthorMailAddress)

        foreach ($To in $EmailAddresses) {
            #Gnerate reciver list
            $message.To.Add($To)
        }
       
        $smtp.Send($message)
            
        #Kill all!
        $view.Dispose()
        $smtp.Dispose()
        $message.Dispose()
    }
}


class ProcessTaskClass {
    [RevisionClass]$RevisionObj;
    [System.Collections.Generic.List[PathReciverClass]]$AllTasks;
    [System.Collections.Generic.List[PathReciverClass]]$TasksToProcess;

    ProcessTaskClass([RevisionClass]$RevisionObj, [System.Collections.Generic.List[PathReciverClass]]$AllTasks) {
        $this.AllTasks = $AllTasks
        $this.RevisionObj = $RevisionObj

        $this.TasksToProcess = $this.AllTasks | Sort-Object Path -Unique

        #  $this.Processing()
    }

    [void]Processing() {
        [System.Collections.Generic.List[ChangePathClass]]$ValidPathsList = [System.Collections.Generic.List[ChangePathClass]]::new()
        
        foreach ($TaskItem in $this.TasksToProcess) {
            foreach ($ChagePathItem in $this.RevisionObj.ChangePaths) {
                if ($ChagePathItem.Path.Contains($TaskItem.Path)) {
                    $ValidPathsList.Add($ChagePathItem)
                }
            }
            [FormatMessageBodyClass]$Message = [FormatMessageBodyClass]::new($this.RevisionObj, $ValidPathsList)
            [SenderServerClass]$Sender = [SenderServerClass]::new($this.RevisionObj)
            $Sender.Send($Message.ResultMessage, $this.RevisionObj, $TaskItem.EMails)
            
            #Не работает из хука ((
            # [Logger]$Log = [Logger]::New($TaskItem.EMails,  $this.Repository, $ValidPathsList)

            $ValidPathsList.Clear()
        }
    }
}

class FormatMessageBodyClass {
    
    [System.Collections.Generic.List[ChangePathClass]]$PRList;
    [string]$MessageBody = "";
    [RevisionClass]$RevisionObj;
    [string]$MessageHeader = "";
    [string]$ResultMessage = "";

    FormatMessageBodyClass([RevisionClass]$RevisionObj, [System.Collections.Generic.List[ChangePathClass]]$PathsReciversList) {
        $this.PRList = [System.Collections.Generic.List[ChangePathClass]]::new()
        $this.PRList = $PathsReciversList | Sort-Object Verb

        $this.RevisionObj = $RevisionObj
        $this.SetMessageHeader()
        $this.SetMessageBody()
    }

    SetMessageHeader() {
        $this.MessageHeader = '<meta charset=' + '"' + 'utf-8' + '"' + '/>' + 
        '<style>
                    BODY{font-family: Arial; font-size: 10pt;}
                    TABLE{border-collapse: collapse;}
                    TH{border: 1px solid black; background: #f6f8fa; padding: 5px; text-align: left;}
                    TD{border: 1px solid black; padding: 5px 5px 5px 25px;}
                    A{color: #0563c1;}
                    .theader{background: #f4f0ed}
                    .replace{background: #fcf9cc}
                    .modify{background: #ecf2fb}
                    .sadd{background:#eff8e5}
                    .sdelete{background:#fff2f2}
                </style>'
    }

    SetMessageBody() {
        $this.ResultMessage += $this.MessageHeader

        [string]$ServerName = $env:COMPUTERNAME 
        [string]$FQDNServerName = [System.Net.Dns]::GetHostByName(($ServerName)).HostName
        [string]$Description = ""

        if (![string]::IsNullOrEmpty($this.RevisionObj.Description)) {
            $Description = "Комментарий: $($this.RevisionObj.Description)"
        }

        [System.Text.StringBuilder]$body = [System.Text.StringBuilder]::new()

        $body.Append("<body>")
        $body.Append("Автор: <a href=mailto:$($this.RevisionObj.AuthorMailAddress)>$($this.RevisionObj.AuthorMailAddress)</a>")
        
        $body.Append("<p>$Description</p>")
        $body.Append("<p><a href=https://$FQDNServerName/!/#")
        $body.Append("$($this.RevisionObj.RepositoryName)/commit/r$($this.RevisionObj.RevisionNumber)/>Список изменений</a><p/>")
        
        $Table = $this.FromatHTMLTable()

        $body.Append($Table)
        $body.Append("</body>")
        
        $this.ResultMessage += $body.ToString()
    }

    [string]FromatHTMLTable() {
        $ServerName = $env:COMPUTERNAME 
        $FQDNServerName = [System.Net.Dns]::GetHostByName(($ServerName)).HostName

        [System.Text.StringBuilder]$Result = [System.Text.StringBuilder]::new()
        $Result.Append("<TABLE>")
        
        foreach ($VerbItem in [VerbType].GetEnumNames()) {
            $Paths = $this.PRList | Where-Object { $_.Verb -eq $VerbItem }  
            if ($Paths.Count -ge 1) {
                $VerbData = $this.GetDataFromVerb($VerbItem)
                [string]$StyleClass = $VerbData[0]
                [string]$ColumnName = $VerbData[1]

                $Result.Append("<tr><th>$ColumnName</th></tr>")
                foreach ($PathItem in $Paths) {
                    $Link = "https://$FQDNServerName/svn/$($this.RevisionObj.RepositoryName)$($PathItem.Path)"
                    $HLink = $Link.Replace(" ", "%20") 
                    $href = "<a href=$HLink>$Link</a>"
                    
                    $Result.Append("<tr $StyleClass><td>")
                    $Result.Append($href)
                    $Result.Append("</td></tr>")
                }
            }
        }
        
        $Result.Append("</TABLE>")
        return $Result.ToString()
    }

    hidden [string[]]GetDataFromVerb([VerbType]$Verb) {   
        $Result = @("", "")
        if ($Verb -eq [VerbType]::AddFile) {
            $Result[0] = " class='sadd'"
            $Result[1] = "Добавленные файлы"
        }
        
        elseif ($Verb -eq [VerbType]::AddDir) {
            $Result[0] = " class='sadd'"
            $Result[1] = "Добавленные каталоги"
        }

        elseif ($Verb -eq [VerbType]::DeleteFile) {
            $Result[0] = " class='sdelete'"
            $Result[1] = "Удаленные файлы"
        }

        elseif ($Verb -eq [VerbType]::DeleteDir) {
            $Result[0] = " class='sdelete'"
            $Result[1] = "Удаленные каталоги"
        }

        elseif ($Verb -eq [VerbType]::ReplaceFile) {
            $Result[0] = " class='replace'"
            $Result[1] = "Замененные файлы"
        }

        elseif ($Verb -eq [VerbType]::ModifyFile) {
            $Result[0] = " class='modify'"
            $Result[1] = "Отредактированные файлы"
        }

        return $Result
    }
}


class TaskGetter {
    [System.Collections.Generic.List[PathReciverClass]]$TaskSteck;
    [MailerSettings]$Settings;
    [RevisionClass]$RevisionObj;

    TaskGetter([MailerSettings]$Settings, [RevisionClass]$RevisionObj) {
        $this.RevisionObj = $RevisionObj
        $this.Settings = $Settings
        $this.TaskSteck = [System.Collections.Generic.List[PathReciverClass]]::new()
        $this.SetTaskList()
    }

    [void]SetTaskList() {
        foreach ($ChangePath in $this.RevisionObj.ChangePaths.Path) {
            foreach ($PathReciver in $this.Settings.PathReciver) {        
                if ($ChangePath.Contains($PathReciver.Path)) {
                    $this.TaskSteck.Add($PathReciver)
                }
            }
        }
    }
} 



Class Logger {
    [string]$LogPath = "C:\Scripts\Mailer\Test\log.log";
    [string]$Message;

    Logger($Mails, $RevisionObj, $Path) {
        $this.LogPath = $PSScriptRoot + "\log.log";
        $this.SetMessage($Mails, $RevisionObj, $Path)
        $this.SaveLog()
    }

    [void]SetMessage($Mails, $RevisionObj, $Path) {
        $this.Message = [datetime]::Now.ToString() + ":" + $RevisionObj.RepositoryName + ":" + $Mails + ":" + $Path.Path + ";" 

    }

    [void]SaveLog() {
        $this.Message | Out-File -Encoding utf8 -Append -FilePath $this.LogPath
    }
}


# Создаес объект репозитория
[RevisionClass]$RevisionObj = [RevisionClass]::New($RepPath, $Revision)

# Получаем данные из файла настроек
[MailerSettings]$Settings = [MailerSettings]::new($RevisionObj.RepositoryName);

# Генерируем все задания (все пути)
[TaskGetter]$TaskSteck = [TaskGetter]::New($Settings, $RevisionObj)

# Процессинг
[ProcessTaskClass]$Processing = [ProcessTaskClass]::new($RevisionObj, $TaskSteck.TaskSteck)
$Processing.Processing()
