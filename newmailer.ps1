param(
    #get parametrs from hook 
    [string]$Revision = "", #Revision number %2 1
    [string]$RepPath = "" #Rpo path %1 
 
)

Enum VerbType
{
    AddFile = 0
    AddDir = 1
    ModifyFile = 2
    ReplaceFile = 3
    DeleteFile = 4
    DeleteDir = 5
}

class PathReciverClass{
    [string]$Path;
    [System.Collections.Generic.List[string]]$EMails;

    PathReciverClass([string]$Path,[System.Collections.Generic.List[string]]$Mails)
    {
        $this.EMails = New-Object System.Collections.Generic.List[string]
        $this.Path = $Path;
        $this.EMails = $Mails;
    }
} #class


class ChangePathClass{
    [string]$Path;
    [VerbType]$Verb;

    ChangePathClass([string]$Path,[VerbType]$Verb)
    {
        $this.Path = $Path;
        $this.Verb = $Verb;
    }
} #class



#Should be renamed to "RevisionClass"
class RepositoryClass {
    [string]$RepositoryName;
    [string]$RepositoryPath;
    [string]$Author;
    [string]$AuthorMailAddress;
    [string]$Description;
    [int]$RevisionNumber;
    [string]$DBFormat;
    [string]$RevisionLoclaPath;
    [System.Collections.Generic.List[ChangePathClass]]$ChangePaths;
    
    RepositoryClass([string]$RepositoryPath, [int]$RevisionNumber) #Constructor
    {
        $this.RevisionNumber = $RevisionNumber;
        $this.RepositoryPath = $RepositoryPath;
        $this.RepositoryName = $this.GetRepositoryName();
        $this.DBFormat = $this.GetDBFormat();
        $this.RevisionLoclaPath = $this.GetRevisionPath();
        
        $this.SetAuthorAndDescription();
        $this.ChangePaths = New-Object System.Collections.Generic.List[ChangePathClass];

        $this.AuthorMailAddress = $this.GetMailFromName();
    }

    [string] GetRepositoryName()
    { #Get name from full path
        $TPath = $this.RepositoryPath.Split("\") #form path to Name
        [string] $result = $TPath[$TPath.Length-1]
        return $result
    }

    [string] GetDBFormat()
    { #Get database format  from file "format"
        $Path = $this.RepositoryPath + "\db\format"
        $FormatContent = Get-Content $Path
        
        if ($FormatContent -like "*layout linear*"){
            return "linear"
        }
        else {
            [string]$div = $FormatContent.Split(" ")[3].ToString()
            return $div
        }
    }
   
    [string] GetRevisionPath() 
    { #get full path to revs
        if ($this.DBFormat -eq "linear"){
            return ""
        }
        
        [int]$Res = $null
        
        $Res = [math]::Truncate($this.RevisionNumber / $this.DBFormat)
        $RevNum = $Res.ToString() + "\"
        
        return $RevNum
    }

    [void] SetAuthorAndDescription()
    {
        $Path = $this.RepositoryPath + "\db\revprops\" + $this.RevisionLoclaPath + $this.RevisionNumber
        $Content = Get-Content -path $Path -Encoding UTF8
        
        $this.Author = $Content[3]
        $this.Description =  $Content[$Content.Length - 2]

    }
    

    [string] GetMailFromName()
    {

        #Getting email address from AD user
        $Searcher = New-Object System.DirectoryServices.DirectorySearcher
        $Searcher.Filter="(&(objectClass=user)(SamAccountName=" + $this.Author + "))"
        $Searcher.PropertiesToLoad.Add("mail")
        
        $Users = $Searcher.FindAll()
        $Res = $Users.Properties.Item("mail")
        return $Res
    }


    [void] SetChangePaths()
    {
        $ContentPath = $this.RepositoryPath + "\db\revs\" + $this.RevisionLoclaPath + $this.RevisionNumber
        
        $FilesContent = Get-Content -Path $ContentPath -Encoding UTF8
        # Очень странная конструкция с двойным отрицанием. ;))) Условия сравнения изменилось, но я так и не добрался до рефакторинга
        $Verb = $FilesContent | Select-String -Pattern " Add-file " -AllMatches
        if (-Not !$Verb){
            $this.GetFileList($Verb, [VerbType]::AddFile)
        }
        
        $Verb = $FilesContent | Select-String -Pattern " Add-dir " -AllMatches
        if (-Not !$Verb){
             $this.GetFileList($Verb, [VerbType]::AddDir)
        }
        
        $Verb = $FilesContent | Select-String -Pattern " Modify-file " -AllMatches
        if (-Not !$Verb){
            $this.GetFileList($Verb, [VerbType]::ModifyFile)
        }
        
        $Verb = $FilesContent | Select-String -Pattern " replace-file " -AllMatches
        if (-Not !$Verb){
            $this.GetFileList($Verb, [VerbType]::ReplaceFile)
        }
        
        $Verb = $FilesContent | Select-String -Pattern " Delete-dir " -AllMatches
        if (-Not !$Verb){
            $this.GetFileList($Verb, [VerbType]::DeleteDir)
        }

        $Verb = $FilesContent | Select-String -Pattern " Delete-file " -AllMatches
        if (-Not !$Verb){
            $this.GetFileList($Verb, [VerbType]::DeleteFile)
        }
        #Write-Host $this.ChangePaths[0].Path
    }


    [void] GetFileList($Content, [VerbType]$Verb){ #Get file list from content
        [string]$FullStr = ""
        foreach ($FullStr in $Content) {
            [int]$i = $FullStr.IndexOf(" /")
            $Res = $FullStr.Substring($i+1)
            
            [ChangePathClass]$ResPath = [ChangePathClass]::New($Res, $Verb);
            $this.ChangePaths.Add($ResPath)
        
        }   #Content
    }

}



class MailerSettings{
    [string]$PathToJSON;
    $AllSettings;
    [string]$RepositoryName;
    [System.Collections.Generic.List[PathReciverClass]]$PathReciver;

    MailerSettings($RepositoryName)
    {
        $this.PathToJSON = $PSScriptRoot + "\rp.json"; #or path to JSON file
        $this.RepositoryName = $RepositoryName;
        $this.ReadSettings();
        
        $this.PathReciver = New-Object System.Collections.Generic.List[PathReciverClass]
        $this.SetPathsNew();
    }

    [void]ReadSettings()
    {
        $result = Get-Content -Path $this.PathToJSON -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
        $this.AllSettings = $result
    }

    [void]SetPathsNew() 
    {
        $repo = $this.AllSettings | Where-Object {$_.RepoName -eq $this.RepositoryName}
        
        foreach($Item in $repo.PathsRecivers)
        {
             [PathReciverClass]$PRItme = [PathReciverClass]::new($Item.Path,  $Item.Mail)
             $this.PathReciver.Add($PRItme)
        }
    }

} 
  

class SenderServerClass{
    [string]$ServerName = "localhost";
    [string]$FQDNServerName = "localhost";


    SenderServerClass([RepositoryClass]$Repository)
    {
        $this.ServerName = $env:COMPUTERNAME 
        $this.FQDNServerName = [System.Net.Dns]::GetHostByName(($this.ServerName)).HostName
    }


    Send([string]$MessageBody, [RepositoryClass]$Repository, [string]$EmailAddresses )
    {

        $username = "domain\user"
        $password = "password"
        $mailservername = "mail.domain"
        $port = 9925

        [Net.Mail.SmtpClient]$SMTP = New-Object Net.Mail.SmtpClient($mailservername, $port)

        $SMTP.Credentials = New-Object System.Net.NetworkCredential($username, $password)
        $SMTP.EnableSsl = $true
        
        [string]$SMTPFrom = $this.ServerName+"@mail.domain"
        
        [string]$Subject = $Repository.RepositoryName + ": " + $Repository.Author + ": r" + $Repository.RevisionNumber
        $message = New-Object System.Net.Mail.MailMessage 
        $message.From = $SMTPFrom
        $message.IsBodyHTML = $true

        $message.Subject = $Subject
        
        $message.Body = $messagebody 

        $view = [System.Net.Mail.AlternateView]::CreateAlternateViewFromString($messagebody, $null, "text/html")
        $message.AlternateViews.Add($view)

        $message.ReplyToList.Add($Repository.AuthorMailAddress)

        $MailAddreses = $EmailAddresses.Split(" ")
        foreach ($To in $MailAddreses){ #Gnerate reciver list
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
    [RepositoryClass]$Repository;
    [System.Collections.Generic.List[PathReciverClass]]$AllTasks;
    [System.Collections.Generic.List[PathReciverClass]]$TasksToProcess;

    ProcessTaskClass([RepositoryClass]$Repository, [System.Collections.Generic.List[PathReciverClass]]$AllTasks)
    {
        $this.AllTasks = $AllTasks
        $this.Repository = $Repository

        $this.TasksToProcess = $this.AllTasks | Sort-Object Path -Unique

        $this.Processing()
    }

    [void]Processing()
    {
        [System.Collections.Generic.List[ChangePathClass]]$ValidPathsList = New-Object System.Collections.Generic.List[ChangePathClass]
        
        foreach ($TaskItem in $this.TasksToProcess) {
            foreach ($ChagePathItem in $this.Repository.ChangePaths)
            {
                if ($ChagePathItem.Path.Contains($TaskItem.Path))
                {
                    $ValidPathsList.Add($ChagePathItem)
                }
            }
            [FormatMessageBodyClass]$Message = [FormatMessageBodyClass]::new($this.Repository, $ValidPathsList)
            [SenderServerClass]$Sender = [SenderServerClass]::new($this.Repository)
            $Sender.Send($Message.ResultMessage, $this.Repository, $TaskItem.EMails)
            
            #not working from hook ((
           # [Logger]$Log = [Logger]::New($TaskItem.EMails,  $this.Repository, $ValidPathsList)

            $ValidPathsList.Clear()
        }

    }
}

class FormatMessageBodyClass {
    
    [System.Collections.Generic.List[ChangePathClass]]$PRList;
    [string]$MessageBody = "";
    [RepositoryClass]$Repository;
    $MessageHeader = "";

    $ResultMessage = "";

    FormatMessageBodyClass([RepositoryClass]$Repository, [System.Collections.Generic.List[ChangePathClass]]$PathsReciversList)
    {
        $this.PRList = New-Object System.Collections.Generic.List[ChangePathClass]
        $this.PRList = $PathsReciversList | Sort-Object Verb

        $this.Repository = $Repository
        $this.SetMessageHeader()
        $this.SetMessageBody()
    }

    SetMessageHeader()
    {
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

    SetMessageBody()
    {
        $this.ResultMessage += $this.MessageHeader

        $ServerName = $env:COMPUTERNAME 
        $FQDNServerName = [System.Net.Dns]::GetHostByName(($ServerName)).HostName
        [string]$Description = ""
        if($this.Repository.Description -ne "")
        {
            $Description = "</p><p>Комментарий: " + 
            $this.Repository.Description  
        }
        $body += "<body>"
        $body += '<Path>Автор: <a href=mailto:'+
            $this.Repository.AuthorMailAddress+'>'+ 
            $this.Repository.AuthorMailAddress +' </a>' +
            $Description + 

            "</p><p><a href=https://$FQDNServerName/!/#" +
            $this.Repository.RepositoryName + 
            "/commit/r" + 
            $this.Repository.RevisionNumber + 
            "/>Список изменений</a> </p>"
        
            $Table = $this.FromatHTMLTable()

            $body += $Table
            $body += "</body>"
            $this.ResultMessage += $body
        
        
    }

    [string]FromatHTMLTable()
    {
        $ServerName = $env:COMPUTERNAME 
        $FQDNServerName = [System.Net.Dns]::GetHostByName(($ServerName)).HostName

        [string]$Result = "<TABLE>"
        
        foreach ($VerbItem in [VerbType].GetEnumNames()) 
        {
            $Paths = $this.PRList | Where-Object {$_.Verb -eq $VerbItem}  
            if ($Paths.Count -ge 1)
            {
                $VerbData = $this.GetDataFromVerb($VerbItem)
                [string]$StyleClass = $VerbData[0]
                [string]$ColumnName = $VerbData[1]

                $Result += "<tr><th>"+$ColumnName+"</th></tr>"
                foreach ($PathItem in $Paths)
                {
                    $Link = "https://$FQDNServerName/svn/" + $this.Repository.RepositoryName + $PathItem.Path
                    $HLink = $Link.Replace(" ", "%20") 
                    $href = "<a href=" + $HLink + ">" + $Link + "</a>"
                    
                    $Result +=  "<tr"+$StyleClass+"><td>" +
                                $href +
                                "</td></tr>"
                }
            }
            
        }
        
        $Result += "</TABLE>"
        return $Result
    }

    [string[]]GetDataFromVerb([VerbType]$Verb)
    {   
        $Result = @("","")
        if($Verb -eq [VerbType]::AddFile)
        {
            $Result[0] = " class='sadd'"
            $Result[1] = "Добавленные файлы"
        }
        
        elseif($Verb -eq [VerbType]::AddDir)
        {
            $Result[0] = " class='sadd'"
            $Result[1] = "Добавленные каталоги"
        }

        elseif($Verb -eq [VerbType]::DeleteFile)
        {
            $Result[0] = " class='sdelete'"
            $Result[1] = "Удаленные файлы"
        }

        elseif($Verb -eq [VerbType]::DeleteDir)
        {
            $Result[0] = " class='sdelete'"
            $Result[1] = "Удаленные каталоги"
        }

        elseif($Verb -eq [VerbType]::ReplaceFile)
        {
            $Result[0] = " class='replace'"
            $Result[1] = "Замененные файлы"
        }

        elseif($Verb -eq [VerbType]::ModifyFile)
        {
            $Result[0] = " class='modify'"
            $Result[1] = "Отредактированные файлы"
        }

        return $Result
    }
   
}


class TaskGetter
{
    [System.Collections.Generic.List[PathReciverClass]]$TaskSteck;
    [MailerSettings]$Settings;
    [RepositoryClass]$Repository;

    TaskGetter([MailerSettings]$Settings, [RepositoryClass]$Repository)
    {
        $this.Repository = $Repository
        $this.Settings = $Settings
        $this.TaskSteck = New-Object System.Collections.Generic.List[PathReciverClass]
        $this.SetTaskList()
    }

    SetTaskList(){
        foreach($ChangePath in $this.Repository.ChangePaths.Path)
        {
            foreach($PathReciver in $this.Settings.PathReciver)
            {        
                if ($ChangePath.Contains($PathReciver.Path))
                {
                    $this.TaskSteck.Add($PathReciver)
                }
            }
        }
    }
} 



Class Logger
{
    [string]$LogPath = "C:\log\log.log";
    [string]$Message;

    Logger($Mails, $Repository, $Path)
    {
        $this.LogPath = $PSScriptRoot + "\log.log";
        $this.SetMessage($Mails, $Repository, $Path)
        $this.SaveLog()
    }

    [void]SetMessage($Mails, $Repository, $Path)
    {
        $this.Message = [datetime]::Now.ToString() + ":" + $Repository.RepositoryName + ":" + $Mails + ":" + $Path.Path +";" 

    }

    [void]SaveLog()
    {
        $this.Message | Out-File -Encoding utf8 -Append -FilePath $this.LogPath
    }

}


# Создаес объект репозитория
[RepositoryClass]$Rep = [RepositoryClass]::New($RepPath, $Revision)
# Заполняем необходимые данные
$Rep.SetChangePaths();

# Получаем данные из файла настроек
[MailerSettings]$Settings = [MailerSettings]::new($Rep.RepositoryName);

# Генерируем все задания (все пути)
[TaskGetter]$TaskSteck = [TaskGetter]::New($Settings, $Rep)

# Готовим посылатель
[SenderServerClass]$Sender = [SenderServerClass]::new($Rep);

# Процессинг
[ProcessTaskClass]$Processing = [ProcessTaskClass]::new($Rep, $TaskSteck.TaskSteck)

