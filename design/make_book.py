# Labels design/screens/*.png into the design book: python3 design/make_book.py (from the repo root)
from PIL import Image, ImageDraw, ImageFont
import glob, os
titles = {
 '01':('Первый запуск','Подписок ещё нет'),
 '02':('Главный экран — отключено','Шапка подписки, кнопка, карточка сервера, нижнее меню'),
 '03':('Главный экран — подключение','Орбита крутится быстро'),
 '04':('Главный экран — подключено','Таймер сессии, кнопка светится'),
 '05':('Главный экран — безлимит','Трафик «из ∞», выбран сервер «Авто»'),
 '06':('Подписки','Шторка по нажатию на название подписки'),
 '07':('Новая подписка','Шторка по кнопке «+»'),
 '08':('Серверы','Список с пингом, «Авто» сверху'),
 '09':('Настройки','Подключение, Сеть, Приложение'),
 '10':('Выбор значения','Шторка выбора (на примере маршрутизации)'),
 '11':('Приложения через VPN','Только выбранные / Кроме выбранных'),
 '12':('Пинг — верх','Тип пинга и режим'),
 '13':('Пинг — низ','Тайм-аут и URL-тест'),
 '14':('Оформление','Выбор кнопки: Орбита / Ромашка'),
 '15':('Логи','Подробные логи, обновить, копировать, очистить'),
 '16':('О приложении','Версия, сборка, ядро'),
}
F='assets/fonts/Manrope-%d.ttf'
big=ImageFont.truetype(F%700,64); small=ImageFont.truetype(F%500,36)
bg=(27,28,31); acc=(61,214,160); fg=(242,242,240); sec=(142,143,148)
pages=[]
for f in sorted(glob.glob('design/screens/*.png')):
    n=os.path.basename(f)[:2]; t,sub=titles[n]
    shot=Image.open(f).convert('RGB')
    W=shot.width+120; H=shot.height+300
    pg=Image.new('RGB',(W,H),bg); d=ImageDraw.Draw(pg)
    d.text((60,60),f'{int(n)}.',font=big,fill=acc)
    d.text((60+d.textlength(f'{int(n)}. ',font=big),60),t,font=big,fill=fg)
    d.text((60,160),sub,font=small,fill=sec)
    pg.paste(shot,(60,240))
    d.rounded_rectangle((58,238,62+shot.width,242+shot.height),radius=4,outline=(60,61,66),width=2)
    pages.append(pg)
pages[0].save('design/Orbit_дизайн.pdf',save_all=True,append_images=pages[1:],resolution=200)
w=480; h=int(pages[0].height*w/pages[0].width); cols=4; rows=(len(pages)+cols-1)//cols
ov=Image.new('RGB',(cols*w+(cols+1)*30,rows*h+(rows+1)*30+120),(18,19,21))
d=ImageDraw.Draw(ov); d.text((30,40),'Orbit — все экраны',font=big,fill=fg)
for i,p in enumerate(pages):
    ov.paste(p.resize((w,h),Image.LANCZOS),(30+(i%cols)*(w+30),150+(i//cols)*(h+30)))
ov.save('design/Orbit_все_экраны.png')
