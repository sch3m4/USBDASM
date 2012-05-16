format PE GUI 4.0
entry INICIO

;cabeceras
include 'win32a.inc'

struct GUID
	Data1 dd ?
	Data2 dw ?
	Data3 dw ?
	Data4 rb 8
ends

struct DEV_BROADCAST_DEVICEINTERFACE
	dbcc_size	dd	?
	dbcc_devicetype dd	?
	dbcc_reserved	dd	?
	dbcc_classguid	GUID	?
	dbcc_name	rb	1
ends

struct DEV_BROADCAST_VOLUME
	dbcv_size	dd	?
	dbcv_devicetype dd	?
	dbcv_reserved	dd	?
	dbcv_unitmask	dd	?
	dbcv_flags	dw	?
ends

struct SYSTEM_TIME
	wYear		dw	?
	wMonth		dw	?
	wDayofWeek	dw	?
	wDay		dw	?
	wHour		dw	?
	wMinute 	dw	?
	wSecond 	dw	?
	wMilliseconds	dw	?
ends

section '.datos' data readable writeable
titulo		db        'tit1',0
_Funciona	db 	'works',0

_class		db 'USBDUMP',0 ;la clase de nuestra ventana
wc 		WNDCLASS 0,WindowProc,0,0,NULL,NULL,NULL,NULL,NULL,_class
hwnd 		dd ?
msg 		MSG ?

Unidad		db	5
Completo	rb	255
hora   		SYSTEM_TIME	?

section '.codigo' code readable writeable executable

   INICIO:
	push 0
	call [GetModuleHandle]
	or eax,0
	je EXIT
	mov [wc.hInstance],eax

	push wc
	call [RegisterClass]
	or eax,0
	je EXIT

	push NULL
	push [wc.hInstance]
	push NULL
	push NULL
	push 0
	push 0
	push 0
	push 0
	push WS_POPUP
	push titulo
	push _class
	push 0
	call [CreateWindowEx]
	or eax,0
	je EXIT
	mov [hwnd],eax

   MENSAJES:
	push 0
	push 0
	push NULL
	push msg
	call [GetMessage]
	or eax,0
	je EXIT
	push msg
	call [TranslateMessage]
	push msg
	call [DispatchMessage]
	jmp MENSAJES

   EXIT:
	push 0
	call [ExitProcess]

;procedimiento que recibira los mensajes a nuestra ventana
proc WindowProc hwnd,wmsg,wparam,lparam

	cmp [wparam],0x8000; DBT_DEVICEARRIVAL (nuevo dispositivo insertado y listo)
	jne SIGUE
	mov eax,[lparam]
	cmp [eax+DEV_BROADCAST_DEVICEINTERFACE.dbcc_devicetype],0x02 ;DBT_DEVTYP_VOLUME (volumen logico)
	je NUEVO
	;evitamos que nos cierren enviandonos un mensaje ;)
	;cmp [wmsg],WM_DESTROY
	;je DESTROY
	jmp SIGUE

   NUEVO:
	;cojemos la letra de la unidad del nuevo dispositivo
	push [eax+DEV_BROADCAST_VOLUME.dbcv_unitmask]
	call FirstDriveFromMask

	;creamos la carpeta
	mov byte [Completo],bl
	mov byte [Completo+1],'_'
	mov byte [Completo+2],0
	lea esi,[Completo]
	push esi
	call PrepararCarpeta
	or eax,0
	je SIGUE ;si no se ha creado, no hacemos nada mas
	push esi
	call [strlen]
	mov byte [esi+eax],'\'
	inc eax
	mov byte [esi+eax],0

	;###########################################
	;## ESI => Puntero a la cadena de origen  ##
	;###########################################
	mov byte [Unidad],bl
	push 0
	push esi
	push ebx
	call CopiarContenido

   SIGUE:
	push [lparam]
	push [wparam]
	push [wmsg]
	push [hwnd]
	call [DefWindowProc]
	ret

   DESTROY:
	push NULL
	call [PostQuitMessage]

	xor eax,eax
	ret
endp

;crea una carpeta con la fecha actua, devolviendo 0/1 según se cree la carpeta
proc PrepararCarpeta Ruta
locals
	aux1 rb 5
	aux2 rb 3
	aux3 rb 3
	Guion db '_',0
endl
	push hora
	call [GetSystemTime]

	;el año
	push hora.wYear
	call [_wtoi]
	or eax,0
	jne MAL

	lea eax,[aux1]
	push 0xA
	push eax
	push ecx
	call [itoa]
	or eax,0
	je MAL

	;el mes
	push hora.wMonth
	call [_wtoi]
	or eax,0
	jne MAL
	lea eax,[aux2]
	push 0xA
	push eax
	push ecx
	call [itoa]
	or eax,0
	je MAL

	;el dia
	push hora.wDay
	call [_wtoi]
	or eax,0
	jne MAL
	lea eax,[aux3]
	push 0xA
	push eax
	push ecx
	call [itoa]
	or eax,0
	je MAL

	;////////////////////
	;generamos la cadena
	;////////////////////
	lea eax,[aux1]
	push eax
	push [Ruta]
	call [strcat]
	lea eax,[Guion]
	push eax
	push [Ruta]
	call [strcat]
	lea eax,[aux2]
	push eax
	push [Ruta]
	call [strcat]
	lea eax,[Guion]
	push eax
	push [Ruta]
	call [strcat]
	lea eax,[aux3]
	push eax
	push [Ruta]
	call [strcat]

	;creamos la carpeta
	push 0
	push [Ruta]
	call [CreateDirectory]
	or eax,0
	jne SALIDA
	;hay error
	call [GetLastError]
	cmp eax,0xB7
	je SALIDA_BUENA

MAL:
	mov eax,0
	jmp SALIDA

SALIDA_BUENA:
	mov eax,1
SALIDA:
	ret
endp

;#####################################
;## COPIA EL CONTENIDO A LA CARPETA ##
;#####################################
proc CopiarContenido Origen,Destino,rec
locals
pen	db 255;ruta del dispositivo
len	dd ?
handle	dd ?
datos	WIN32_FIND_DATA ?
endl
	or [rec],1
	je BUSQUEDA
	mov ax,byte [Origen]
	mov [pen],ax
	mov byte [pen+1],':'
	mov byte [pen+2],'\'
	mov byte [pen+3],'*'
	mov byte [pen+4],0

	push [Destino]
	call [strlen]
	mov [len],eax

;comenzamos la búsqueda de fichero
BUSQUEDA:
	lea eax,[datos]
	lea ebx,[pen]
	push eax
	push ebx
	call [FindFirstFile]
	cmp eax,INVALID_HANDLE_VALUE
	je SALIR
BUSCA:
	lea eax,[datos]
	push eax
	push [handle]
	call [FindNextFile]
	or eax,0
	je SALIR
	cmp [datos.dwFileAttributes],FILE_ATTRIBUTE_DIRECTORY
	jne ARCHIVO
	nop ;trabajar con la carpeta
	jmp BUSCA
ARCHIVO:
	nop ;trabajar con el archivo
	jmp BUSCA

SALIR:
	push [handle]
	call [FindClose]
	ret
endp

;indica la letra de la nueva unidad
proc FirstDriveFromMask umaks
	mov ecx,[umaks]
	xor al,al

IBUCLE:
	test cl,1
	jne FBUCLE
	shr ecx,1
	inc al
	cmp al,0x1a
	jl IBUCLE

FBUCLE:
	add eax,'A'
	xor bl,bl
	mov bl,al
	xor eax,eax

ret
endp

section '.import' import data readable writeable

library kernel32,'kernel32.dll',\
	user32,'user32.dll',\
	msvcrt,'msvcrt.dll'

import kernel32,\
       ExitProcess,'ExitProcess',\
       GetModuleHandle,'GetModuleHandleA',\
       CreateDirectory,'CreateDirectoryA',\
       GetSystemTime,'GetSystemTime',\
       GetLastError,'GetLastError',\
       CopyFile,'CopyFileA',\
       FindFirstFile,'FindFirstFileA',\
       FindNextFile,'FindNextFileA',\
       FindClose,'FindClose'

import user32,\
       MessageBox,'MessageBoxA',\ ;VERSION DE DEBUG
       RegisterClass,'RegisterClassA',\
       CreateWindowEx,'CreateWindowExA',\
       GetMessage,'GetMessageA',\
       TranslateMessage,'TranslateMessage',\
       DispatchMessage,'DispatchMessageA',\
       PostQuitMessage,'PostQuitMessage',\
       DefWindowProc,'DefWindowProcA'

import msvcrt,\
	itoa,'_itoa',\
	_wtoi,'_wtoi',\
	strcpy,'strcpy',\
	strcat,'strcat',\
	strlen,'strlen'
