create table image_filepath(f_id integer,d_id integer,
       filename varchar(300),primary key(f_id,d_id),
       foreign key (d_id) references image_dirpath(d_id));
create table image_dirpath(d_id integer primary key,dirname varchar(200));
